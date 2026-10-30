//! A splice's sync state.

use crate::repo::*;
use crate::util::*;

impl Repo {
    /// Classifies the splice's sync state while the monorepo is on <branch>,
    /// into `c`. Status, merge, push, diff and log all need it.
    pub fn classify_splice(&mut self, path: &str, branch: &str) -> Res<()> {
        self.require_splice_upstream(path)?;
        let target = self.resolve_upstream_target(path, branch)?;
        let mut c = Classified {
            upstream_branch: target.name.clone(),
            upstream_label: self.upstream_branch_label(path, &target.label()),
            synced: splice_config(path, "commit", "HEAD"),
            target: target.clone(),
            ..Classified::default()
        };
        let result = self.classify_into(path, &target, &mut c);
        self.c = c;
        result
    }

    fn classify_into(&mut self, path: &str, target: &Target, c: &mut Classified) -> Res<()> {
        let pinned = target.kind != TargetKind::Branch;
        // A pin that's here counts as fetched, though upstream has no branches.
        let pin_here = pinned && commit_of(&target.reference).is_some();
        if !self.splice_fetched(path) && !pin_here {
            // Without a synced commit, the splice came from init: its upstream
            // was empty, so a fetch that brings nothing is the expected state.
            // With one that's here, a fetch happened, and the upstream has no
            // branches left. Only a fresh clone of the monorepo has neither
            // refs nor commit. A pin that isn't here then is missing, not a
            // branch.
            c.state = if c.synced.is_empty() || commit_here(&c.synced) {
                if pinned {
                    State::MissingPin
                } else {
                    State::MissingBranch
                }
            } else {
                State::NeverFetched
            };
            return Ok(());
        }

        c.target_ref = target.reference.clone();
        if pinned {
            if commit_of(&c.target_ref).is_none() {
                c.state = State::MissingPin;
                return Ok(());
            }
        } else if !ref_exists(&c.target_ref) {
            c.state = State::MissingBranch;
            return Ok(());
        }

        let local_tree = self.content_tree("HEAD", path)?;
        let remote_tree = tree_of(&c.target_ref);
        // A commit given with push --rebuilt-commit differs in its history,
        // not its files: only comparing commits tells whether it's there yet.
        if !self.rebuild_given.contains_key(path)
            && local_tree.is_some()
            && local_tree == remote_tree
        {
            c.state = State::UpToDate;
            return Ok(());
        }

        if !c.synced.is_empty() && !commit_here(&c.synced) {
            c.state = State::MissingSynced;
            return Ok(());
        }

        let rebuilt = contained(self.splice_rebuild(path))?;
        c.rebuilt = rebuilt.unwrap_or_default();
        let remote_head = commit_of(&c.target_ref).unwrap_or_default();
        c.state = if c.rebuilt.is_empty() {
            State::UnrelatedHistory
        } else if c.rebuilt == remote_head {
            State::UpToDate
        } else if is_ancestor(&remote_head, &c.rebuilt) {
            State::Push
        } else if is_ancestor(&c.rebuilt, &remote_head) {
            State::Pull
        } else if git(&["merge-base", &c.rebuilt, &remote_head]).q().ok() {
            State::Diverged
        } else {
            State::UnrelatedHistory
        };
        Ok(())
    }

    /// For a splice whose upstream lacks the current branch, compares the
    /// rebuild with upstream's default branch instead, as a PR from the branch
    /// would, into `d`. Commits from the monorepo branch the current one was
    /// cut from count too: upstream may never have taken them.
    pub fn compare_with_default_branch(&mut self, path: &str) -> Res<()> {
        self.d = Compared {
            new_commits: "0".to_string(),
            behind_commits: "0".to_string(),
            ..Compared::default()
        };
        let target = self.resolve_default_target(path, None)?;
        // Set by the caller's classify_splice for messages of the same splice.
        self.c.target = target.clone();
        if target.name.is_empty() {
            return Err(Fail::Soft);
        }
        self.d.default_branch = target.label();
        let rebuilt = contained(self.splice_rebuild(path))?;
        self.d.rebuilt = rebuilt.unwrap_or_default();
        if self.d.rebuilt.is_empty() {
            return Ok(());
        }
        let rebuilt = self.d.rebuilt.clone();
        if commit_of(&target.reference).is_some() {
            self.d.default_ref = target.reference.clone();
            let counts = git(&[
                "rev-list",
                "--left-right",
                "--count",
                &format!("{rebuilt}...{}", target.reference),
            ])
            .out()
            .ok_or(Fail::Soft)?;
            let mut counts = counts.split_whitespace();
            self.d.new_commits = counts.next().unwrap_or("0").to_string();
            self.d.behind_commits = counts.next().unwrap_or("0").to_string();
            if let Some(base) = git(&["merge-base", &rebuilt, &target.reference]).out() {
                if tree_of(&rebuilt) == tree_of(&base) {
                    self.d.no_changes = true;
                }
            }
        } else {
            self.d.new_commits = git(&["rev-list", "--count", &rebuilt])
                .out()
                .ok_or(Fail::Soft)?;
        }
        Ok(())
    }

    /// What's known when the splice's synced commit isn't here: a fetch gets it
    /// unless upstream lacks it.
    pub fn missing_synced_message(&self, path: &str) -> String {
        format!(
            "synced commit {} isn't here -- run 'git splice fetch {}{path}', or check that upstream has it",
            short(&self.c.synced),
            self.upstream_option(path)
        )
    }

    /// Prints manual recovery commands for a splice with unrelated history.
    /// With no common ancestor there's no principled automatic merge, only a
    /// human decision about which side to keep.
    pub fn print_unrelated_history_guidance(&self, path: &str) {
        let q_path = shell_quote(path);
        let q_url = shell_quote(&self.url_in_use(path));
        log_warn(format!(
            "{path}: upstream and the splice share no history -- pick a side:"
        ));
        eprint_text(&format!(
            "\n  # keep the upstream version, discarding local changes under {path}:\n  git rm -r -q -- {q_path} && git commit -m {}\n  git splice clone -- {q_url} {q_path}\n\n  # OR: keep both, resolving every file that differs as a conflict:\n  git rm -q -- {} && git commit -m {}\n  git splice clone --merge -- {q_url} {q_path}\n\n  # OR: keep the monorepo version, overwriting upstream's branch:\n  git splice push {}--force -- {q_path}\n\n",
            shell_quote(&format!("remove {path}")),
            shell_quote(&format!("{path}/{STATE_FILE}")),
            shell_quote(&format!("unsplice {path}")),
            self.selection_options(path)
        ));
    }
}
