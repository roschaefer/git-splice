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
        // Made again before anything compares with it: a branch the upstream
        // doesn't have yet compares with its default branch, and an upstream
        // that's still empty has nothing to compare with, from the same
        // synced commit. An upstream never fetched has no key yet: a fetch
        // comes first.
        let fetch_tried = pin_here || !self.key_of(path).is_empty();
        if fetch_tried && !c.synced.is_empty() && !commit_here(&c.synced) {
            self.remake_synced(path, &c.synced.clone());
        }
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

        let here = c.synced.is_empty() || commit_here(&c.synced);
        // A branch whose reflog here shows it had the synced commit was
        // rewritten or rewound upstream: that's not this branch's work.
        let had = || {
            git(&["rev-list", "--walk-reflogs", &c.target_ref])
                .q()
                .out()
                .unwrap_or_default()
                .lines()
                .any(|entry| is_ancestor(&c.synced, entry))
        };
        if !c.synced.is_empty()
            && (!here || (!is_ancestor(&c.synced, &c.target_ref) && !had()))
            && self.remake_synced(path, &c.synced.clone())
        {
            // Only a copy of this branch's own history comes out the same: the
            // commits above the newest one the upstream has are its own.
            let fetched = git(&["merge-base", &c.synced, &c.target_ref])
                .out()
                .unwrap_or_default();
            let own = git(&["rev-list", "--count", &format!("{fetched}..{}", c.synced)])
                .out()
                .unwrap_or_default();
            let plural = if own == "1" { "" } else { "s" };
            log_warn(format!(
                "{path}: synced commit {} isn't on {} -- made it again here: {} and {own} commit{plural} of this branch's own",
                short(&c.synced),
                c.upstream_label,
                short(&fetched)
            ));
            self.remade.insert(path.to_string(), fetched);
        } else if !here {
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

/// A blob: splice <path>'s state file as committed in <rev>, or a new one, with
/// each (key, value) set (an empty value unsets it). A key without a section is
/// in [splice], e.g. "commit"; others are given in full, e.g.
/// "upstream.origin.url".
pub fn state_blob_in(path: &str, rev: &str, settings: &[(&str, &str)]) -> Res<String> {
    let file = Temp::new();
    let current = git(&["cat-file", "blob", &format!("{rev}:{path}/{STATE_FILE}")])
        .q()
        .bytes()
        .unwrap_or_default();
    std::fs::write(&file.path, current).map_err(|_| Fail::Soft)?;
    let file_name = file.str();
    let mut failed = false;
    for (key, value) in settings {
        let key = if key.contains('.') {
            key.to_string()
        } else {
            format!("splice.{key}")
        };
        if value.is_empty() {
            git(&["config", "--file", &file_name, "--unset", &key])
                .q()
                .ok();
        } else if !git(&["config", "--file", &file_name, &key, value]).ok() {
            failed = true;
        }
    }
    if failed {
        return Err(Fail::Soft);
    }
    git(&["hash-object", "-w", &file_name])
        .out()
        .ok_or(Fail::Soft)
}

pub fn state_blob(path: &str, settings: &[(&str, &str)]) -> Res<String> {
    state_blob_in(path, "HEAD", settings)
}

/// Tree <tree> with each (folder, tree) of <folders> in place of that folder,
/// then each (file, blob) of <files> written. Uses a temporary index, so
/// neither the worktree nor the real index changes.
pub fn tree_with(
    tree: &str,
    folders: &[(String, String)],
    files: &[(String, String)],
) -> Res<String> {
    if folders.is_empty() && files.is_empty() {
        return Ok(tree.to_string());
    }
    let index = Temp::new();
    let indexed = |args: &[&str]| git(args).env("GIT_INDEX_FILE", &index.path);
    let mut ok = indexed(&["read-tree", tree]).ok();
    for (folder, content) in folders {
        let spec = format!(":(top,literal){folder}");
        ok = ok
            && indexed(&[
                "rm",
                "-r",
                "-q",
                "-f",
                "--cached",
                "--ignore-unmatch",
                "--",
                &spec,
            ])
            .ok()
            && indexed(&["read-tree", &format!("--prefix={folder}/"), content]).ok();
    }
    for (file, blob) in files {
        let entry = format!("100644,{blob},{file}");
        ok = ok && indexed(&["update-index", "--add", "--cacheinfo", &entry]).ok();
    }
    if !ok {
        return Err(Fail::Soft);
    }
    indexed(&["write-tree"]).out().ok_or(Fail::Soft)
}

/// A tree: commit <rev>'s, with folder <path> replaced by <folder> (none: no
/// folder) plus state file blob <blob> (none: none). Uses a temporary index, so
/// neither the worktree nor the real index changes.
pub fn reroot_tree(path: &str, folder: Option<&str>, blob: Option<&str>, rev: &str) -> Res<String> {
    let index = Temp::new();
    let indexed = |args: &[&str]| git(args).env("GIT_INDEX_FILE", &index.path);
    let spec = format!(":(top,literal){path}");
    let mut ok = indexed(&["read-tree", rev]).ok()
        && indexed(&[
            "rm",
            "-r",
            "-q",
            "-f",
            "--cached",
            "--ignore-unmatch",
            "--",
            &spec,
        ])
        .ok();
    if let (true, Some(folder)) = (ok, folder) {
        ok = indexed(&["read-tree", &format!("--prefix={path}/"), folder]).ok();
    }
    if let (true, Some(blob)) = (ok, blob) {
        let entry = format!("100644,{blob},{path}/{STATE_FILE}");
        ok = indexed(&["update-index", "--add", "--cacheinfo", &entry]).ok();
    }
    if !ok {
        return Err(Fail::Soft);
    }
    indexed(&["write-tree"]).out().ok_or(Fail::Soft)
}

/// Commits the state files <files>, each a (path, blob) pair, on top of HEAD.
/// Git moves the index and worktree to them as a checkout does: it refuses to
/// overwrite local changes and applies checkout attributes. Then 'git commit'
/// commits just these files, as for any commit of the user's.
pub fn commit_state_files(files: &[(String, String)], message: &str) -> Res<()> {
    let index = Temp::new();
    let indexed = |args: &[&str]| git(args).env("GIT_INDEX_FILE", &index.path);
    let mut ok = indexed(&["read-tree", "HEAD"]).ok();
    for (file, blob) in files {
        let entry = format!("100644,{blob},{file}");
        ok = ok && indexed(&["update-index", "--add", "--cacheinfo", &entry]).ok();
    }
    if !ok {
        return Err(Fail::Soft);
    }
    let tree = indexed(&["write-tree"]).out().ok_or(Fail::Soft)?;
    git(&["update-index", "-q", "--refresh"]).q().ok();
    let (ok, output) = git_merged_output(&["read-tree", "-m", "-u", "HEAD", &tree]);
    if !ok {
        eprint_text(&format!("{}\n", output.trim_end()));
        return Err(Fail::Soft);
    }
    let mut commit = vec!["commit", "--quiet", "-m", message, "--"];
    commit.extend(files.iter().map(|(file, _)| file.as_str()));
    if git(&commit).run() != 0 {
        return Err(Fail::Soft);
    }
    Ok(())
}

/// Splices upstream content into <path> as one ordinary commit: a three-way
/// merge of HEAD's folder with <new_folder>, using <base_folder> as the merge
/// base. The state file goes from <base_blob> to <new_blob> in the same commit.
/// Both sides are re-rooted into the monorepo's layout as two throwaway
/// commits, and the second is cherry-picked. Only <path> differs between them,
/// so only the splice can conflict. Fails on a conflict, leaving it to be
/// resolved like any other.
pub fn splice_in(
    path: &str,
    base_folder: Option<&str>,
    base_blob: Option<&str>,
    new_folder: &str,
    new_blob: &str,
    message: &str,
) -> Res<bool> {
    let base_tree = reroot_tree(path, base_folder, base_blob, "HEAD")?;
    let new_tree = reroot_tree(path, Some(new_folder), Some(new_blob), "HEAD")?;
    let base = git(&[
        "commit-tree",
        "--no-gpg-sign",
        &base_tree,
        "-m",
        &format!("base for {message}"),
    ])
    .out()
    .ok_or(Fail::Soft)?;
    let theirs = git(&[
        "commit-tree",
        "--no-gpg-sign",
        &new_tree,
        "-p",
        &base,
        "-m",
        message,
    ])
    .out()
    .ok_or(Fail::Soft)?;
    // Git's own hints would suggest `cherry-pick --continue` or `--skip`; the
    // message below says what fits a splice instead.
    let (ok, output) = git_merged_output(&[
        "-c",
        "advice.mergeConflict=false",
        "-c",
        "advice.resolveConflict=false",
        "cherry-pick",
        &theirs,
    ]);
    if ok {
        return Ok(true);
    }
    if picked_nothing() {
        git(&["cherry-pick", "--quit"]).q().ok();
        return Ok(false);
    }
    // "could not apply <theirs>" names the throwaway commit: no use to anyone.
    for line in output.lines() {
        if !line.starts_with("error: could not apply ") {
            eprint_text(&format!("{line}\n"));
        }
    }
    if git(&["rev-parse", "--quiet", "--verify", "CHERRY_PICK_HEAD"])
        .q()
        .ok()
    {
        log_err(format!(
            "{path}: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)"
        ));
    }
    Err(Fail::Soft)
}

/// A cherry-pick that stopped without a conflict, because its changes are
/// already in HEAD: nothing is unmerged, and the index is HEAD's.
fn picked_nothing() -> bool {
    git(&["rev-parse", "--quiet", "--verify", "CHERRY_PICK_HEAD"])
        .q()
        .ok()
        && git(&["ls-files", "--unmerged"])
            .out()
            .unwrap_or_default()
            .is_empty()
        && git(&["diff", "--cached", "--quiet", "HEAD"]).q().ok()
}

/// A new id for a splice that clone or init mounts at <path> from upstream <url>
/// at <commit> (none for init). The id stays with the splice wherever its
/// .splice goes, so the rebuild can tell it from another splice at the same
/// path. It's derived from all of these and HEAD, not random, so the same
/// command on the same commit writes the same file, and the docs' output is
/// reproducible. The URL and commit tell apart two splices mounted at the same
/// path on branches from the same commit.
pub fn new_splice_id(path: &str, url: &str, commit: &str) -> String {
    let head = git(&["rev-parse", "--verify", "--quiet", "HEAD"])
        .out()
        .unwrap_or_default();
    let id = git(&["hash-object", "--stdin"])
        .input(format!("{path}\0{head}\0{url}\0{commit}\0"))
        .out()
        .unwrap_or_default();
    id[..id.len().min(16)].to_string()
}
