//! git splice merge.

use crate::args::parse_args;
use crate::message::{self, Message, KNOWN};
use crate::repo::*;
use crate::state::*;
use crate::util::*;
use std::collections::HashMap;

pub const USAGE: &str = include_str!("usage/merge.txt");

/// "merge" -> "merged", "pull" -> "pulled".
fn past_tense(verb: &str) -> String {
    if verb == "merge" {
        "merged".to_string()
    } else {
        format!("{verb}ed")
    }
}

/// Succeeds if upstream commit <target> is newer than synced commit <synced>,
/// or there's no synced commit: the only ones --bump moves to.
fn newer_than_synced(synced: &str, target: &str) -> bool {
    synced.is_empty() || (target != synced && is_ancestor(synced, target))
}

/// What a pull does with an upstream commit the folder already has the files of.
#[derive(PartialEq)]
pub enum EqualTree {
    /// Records it as the synced commit: it isn't part of the rebuild, or
    /// there's no rebuild to compare with, without the synced commit here.
    Record,
    /// Only --bump records it: it's part of the rebuild, after the synced
    /// commit.
    Bump,
    /// Nothing records it: it's the synced commit or older.
    Keep,
}

fn state_file_blob(rev: &str, path: &str) -> Option<String> {
    git(&[
        "rev-parse",
        "--verify",
        "--quiet",
        &format!("{rev}:{path}/{STATE_FILE}"),
    ])
    .out()
}

impl Repo {
    /// record_equal_tree's choice, which push --rebuilt-commit asks too.
    pub fn equal_tree_outcome(&mut self, path: &str, target: &str) -> Res<EqualTree> {
        let synced = splice_config(path, "commit", "HEAD");
        if synced.is_empty() || commit_here(&synced) {
            let rebuilt = contained(self.rebuild_splice(path, "HEAD"))?;
            if rebuilt.is_some_and(|rebuilt| is_ancestor(target, &rebuilt)) {
                return Ok(if newer_than_synced(&synced, target) {
                    EqualTree::Bump
                } else {
                    EqualTree::Keep
                });
            }
        }
        Ok(EqualTree::Record)
    }

    /// Merges one splice from its already-fetched upstream branch. <verb> (merge
    /// or pull) only selects the wording of the messages.
    /// What --message-template gets for <command>'s commit that syncs
    /// <path> to <target>.
    fn message_for<'a>(&'a self, command: &'a str, path: &'a str, target: &'a str) -> Message<'a> {
        Message {
            command,
            path,
            upstream: Some(&self.c.upstream_label),
            old: Some(&self.c.synced)
                .filter(|synced| !synced.is_empty())
                .map(String::as_str),
            new: Some(target),
        }
    }

    fn merge_one(&mut self, path: &str, branch: &str, verb: &str) -> Res<()> {
        self.classify_splice(path, branch)?;
        let option = self.upstream_option(path);
        let label = self.c.upstream_label.clone();
        match self.c.state {
            State::NeverFetched => {
                log_warn(format!(
                    "{path}: not fetched yet -- run 'git splice fetch {option}{path}' first"
                ));
                return Err(Fail::Soft);
            }
            State::MissingPin => {
                return fail(format!(
                    "{path}: {} isn't here -- run 'git splice fetch {option}{path}', or check that upstream has it",
                    self.c.target.description()
                ));
            }
            State::MissingBranch => {
                // Its URL was never fetched here, e.g. in a fresh clone, or one
                // a merge above just named: merge can't tell whether upstream
                // has the branch.
                if self.key_of(path).is_empty() {
                    log_warn(format!(
                        "{path}: not fetched yet -- run 'git splice fetch {option}{path}' first"
                    ));
                    return Err(Fail::Soft);
                }
                if self.branch_arg_applies(path) {
                    return fail(format!(
                        "{path}: upstream has no '{label}' branch, which --branch names"
                    ));
                }
                if !self.tracked_branch(path, branch).is_empty() {
                    return fail(format!(
                        "{path}: upstream has no '{label}' branch, which branch.{branch}.splice tracks -- 'git splice fetch --branch <name> --track {}' tracks another, '--no-track' none",
                        shell_quote(path)
                    ));
                }
                log_ok(format!(
                    "{path}: upstream has no '{label}' branch -- nothing to {verb}"
                ));
                return Ok(());
            }
            State::UpToDate => return self.record_equal_tree(path, verb),
            State::Push => {
                if self.merge_bump {
                    return self.bump_synced(path);
                }
                log_ok(format!("{path}: nothing to {verb}"));
                return Ok(());
            }
            State::MissingSynced => {
                // A pull fetched it by its id, if upstream still had it.
                if verb != "pull" {
                    log_warn(format!("{path}: {}", self.missing_synced_message(path)));
                    return Err(Fail::Soft);
                }
                // The pull fetched only the upstream it pulls from.
                if self.several_upstreams(path) {
                    log_err(format!(
                        "{path}: its synced commit {} isn't on {}, the upstream this pull fetched -- 'git splice fetch {}' fetches every upstream",
                        short(&self.c.synced),
                        self.name_of(path),
                        shell_quote(path)
                    ));
                    return Err(Fail::Soft);
                }
                log_err(format!(
                    "{path}: its synced commit {} isn't on its upstream any more",
                    short(&self.c.synced)
                ));
                self.print_unrelated_history_guidance(path);
                return Err(Fail::Soft);
            }
            State::UnrelatedHistory => {
                self.print_unrelated_history_guidance(path);
                return Err(Fail::Soft);
            }
            State::Pull | State::Diverged => {}
        }
        if self.merge_rebase {
            return self.rebase_onto_pull(path, branch, verb);
        }

        // The merge base is the newest upstream commit both sides contain: the
        // synced commit, or a later one this branch pushed since. After a
        // rewrite upstream, e.g. a patch branch rebased onto a new release,
        // Git's merge base is older, and the patches would look like changes on
        // both sides. Like git pull --rebase, the merge then starts at the fork
        // point: where the fetched branch was before the rewrite.
        let target = commit_of(&self.c.target_ref).unwrap_or_default();
        if upstream_has_state_file(&target) {
            return fail(format!(
                "{path}: upstream has a {STATE_FILE} at its root, which would replace {path}/{STATE_FILE}"
            ));
        }
        let merge_base = if let Some(fork) = self.fork_point() {
            // Only a folder that ends up with exactly the rewritten branch's
            // files lets the rebuild start there again. Anything else is
            // rebuilt on top of the fork point, and joined in as a merge.
            if !self.merge_gives(&fork, &target) {
                return fail(format!(
                    "{path}: upstream rewrote '{label}' since {}, and the folder has changes '{label}' lacks -- run 'git splice {verb} --rebase {}{}' to redo them on top: a {verb} now would publish the rewritten-away commits again with the next push",
                    short(&fork),
                    self.selection_options(path),
                    shell_quote(path)
                ));
            }
            fork
        } else {
            git(&["merge-base", &self.c.rebuilt, &target])
                .out()
                .unwrap_or_default()
        };
        refuse_changed_submodule(path, &merge_base, &target)?;
        let base_folder = tree_of(&merge_base).ok_or(Fail::Soft)?;
        let base_blob = state_file_blob("HEAD", path).ok_or(Fail::Soft)?;
        let new_blob = state_blob(path, &[("commit", &target)])?;
        let message =
            self.commit_message(message::DEFAULT, self.message_for(verb, path, &target))?;
        if splice_in(
            path,
            Some(&base_folder),
            Some(&base_blob),
            &format!("{target}^{{tree}}"),
            &new_blob,
            &message,
        )
        .is_err()
        {
            return fail(format!("{path}: {verb} failed"));
        }
        log_ok(format!("{path}: {} {}", past_tense(verb), short(&target)));
        Ok(())
    }

    /// For --rebase: the newest first-parent commit since the synced commit
    /// was recorded whose folder has exactly its files.
    fn sync_point_commit(&mut self, path: &str) -> Res<Option<String>> {
        let synced = self.c.synced.clone();
        let synced_tree = tree_of(&synced);
        let history = git(&["rev-list", "--first-parent", "HEAD"])
            .out()
            .unwrap_or_default();
        for commit in history.lines() {
            if splice_config(path, "commit", commit) != synced {
                break;
            }
            if self.content_tree(commit, path)? == synced_tree {
                return Ok(Some(commit.to_string()));
            }
        }
        Ok(None)
    }

    /// For --rebase: a synced commit made again here has commits of this
    /// branch's own above the newest one its upstream has, which can sit
    /// below the last sync, e.g. the bump that recorded it: replaying them
    /// is left to a plain pull, which merges them.
    fn refuse_remade(&self, path: &str) -> Res<()> {
        if let Some(fetched) = self.remade.get(path) {
            return fail(format!(
                "{path}: synced commit {} was made again here -- --rebase doesn't replay what's above {}; pull without --rebase",
                short(&self.c.synced),
                short(fetched)
            ));
        }
        Ok(())
    }

    /// For --rebase: takes the splice's upstream branch in on top of X, the
    /// newest first-parent commit since the synced commit was recorded whose
    /// folder has exactly its files, and rebases the commits after X onto that.
    /// From X's folder, the synced commit, the upstream branch merges without a
    /// conflict: the pull commit gets exactly its files, so the rebuild starts
    /// there, and the rebased commits follow it. That drops the synced commit's
    /// changes if the upstream branch lacks them, which is wanted only after
    /// the upstream rewrote the branch: it refuses unless the branch's reflog
    /// shows it had them.
    fn rebase_onto_pull(&mut self, path: &str, branch: &str, verb: &str) -> Res<()> {
        let c = self.c.clone();
        let target = commit_of(&c.target_ref).unwrap_or_default();
        if upstream_has_state_file(&target) {
            return fail(format!(
                "{path}: upstream has a {STATE_FILE} at its root, which would replace {path}/{STATE_FILE}"
            ));
        }
        if c.synced.is_empty() {
            return fail(format!(
                "{path}: no synced commit recorded yet, e.g. after init -- nothing to rebase onto; {verb} without --rebase"
            ));
        }
        self.refuse_remade(path)?;
        self.refuse_lacking_synced(path)?;
        let base = self.sync_point_commit(path)?;
        let Some(base) = base else {
            return fail(format!(
                "{path}: no commit since the synced commit {} has exactly its files, e.g. after a {verb} that merged local changes -- nothing to rebase onto; {verb} without --rebase",
                short(&c.synced)
            ));
        };
        if Some(&base) == git(&["rev-parse", "HEAD"]).out().as_ref() {
            self.merge_rebase = false;
            let result = self.merge_one(path, branch, verb);
            self.merge_rebase = true;
            return result;
        }
        refuse_changed_submodule(path, &c.synced, &target)?;
        let since = format!("{base}..HEAD");
        let merges = git(&["rev-list", "--min-parents=2", "--count", &since])
            .out()
            .unwrap_or_default();
        if merges != "0" {
            return fail(format!(
                "{path}: there's a merge commit since {}, whose own changes --rebase would drop -- {verb} without --rebase",
                short(&base)
            ));
        }
        // Without merges, a remote-tracking branch that has any of the commits
        // has the oldest one.
        let commits = git(&["rev-list", &since]).out().unwrap_or_default();
        let oldest = commits.lines().last().unwrap_or("");
        let published = git(&[
            "for-each-ref",
            "--count=1",
            "--contains",
            oldest,
            "--format=%(refname:short)",
            "refs/remotes/",
        ])
        .out()
        .unwrap_or_default();
        if !published.is_empty() {
            return fail(format!(
                "{path}: '{published}' has commits since {}, which --rebase would rewrite -- {verb} on a branch nobody else has, e.g. a pull request's",
                short(&base)
            ));
        }
        let blob = state_blob_in(path, &base, &[("commit", &target)])?;
        let tree = reroot_tree(
            path,
            Some(&format!("{target}^{{tree}}")),
            Some(&blob),
            &base,
        )?;
        let message =
            self.commit_message(message::DEFAULT, self.message_for(verb, path, &target))?;
        let pull = git(&["commit-tree", &tree, "-p", &base, "-m", &message])
            .out()
            .ok_or(Fail::Soft)?;
        let count = git(&["rev-list", "--count", &since])
            .out()
            .unwrap_or_default();
        let rebased = git(&[
            "-c",
            "advice.mergeConflict=false",
            "rebase",
            "-q",
            "--no-update-refs",
            "--no-autostash",
            "--onto",
            &pull,
            &base,
        ])
        .run();
        if rebased != 0 {
            if rebase_in_progress() {
                return fail(format!(
                    "{path}: conflict while rebasing onto the {verb} -- resolve it, then 'git rebase --continue' (or 'git rebase --abort' to give up)"
                ));
            }
            return fail(format!(
                "{path}: git rebase didn't start, see above -- nothing changed"
            ));
        }
        let plural = if count == "1" { "" } else { "s" };
        log_ok(format!(
            "{path}: {} {}, and rebased {count} commit{plural} onto it",
            past_tense(verb),
            short(&target)
        ));
        Ok(())
    }

    /// For pull --rebase --recursive, before it moves anywhere: whether splice
    /// <path> has something to pull. Refuses as --rebase of the splice alone
    /// would when its upstream branch lacks the synced commit.
    pub fn pull_to_rebase(&mut self, path: &str, branch: &str) -> Res<bool> {
        self.classify_splice(path, branch)?;
        if !matches!(self.c.state, State::Pull | State::Diverged) {
            return Ok(false);
        }
        self.refuse_remade(path)?;
        self.refuse_lacking_synced(path)?;
        Ok(true)
    }

    fn refuse_lacking_synced(&self, path: &str) -> Res<()> {
        if self.lacks_synced_by_reflog() {
            return fail(format!(
                "{path}: '{}' lacks the synced commit {}, and its reflog here doesn't show it ever had it -- --rebase would drop that commit's changes",
                self.c.upstream_label,
                short(&self.c.synced)
            ));
        }
        Ok(())
    }

    /// For --rebase: the upstream branch lacks the synced commit, and its
    /// reflog doesn't show it had it: taking its files would drop the synced
    /// commit's changes. That can't tell a branch that never had it from one
    /// rewritten before this clone's reflog of it starts: nothing records which.
    /// A tag or a commit that's pinned has no branch history to tell, and
    /// passes.
    fn lacks_synced_by_reflog(&self) -> bool {
        let c = &self.c;
        if c.target.kind != TargetKind::Branch || is_ancestor(&c.synced, &c.target_ref) {
            return false;
        }
        let entries = git(&["rev-list", "--walk-reflogs", &c.target_ref])
            .q()
            .out()
            .unwrap_or_default();
        !entries.lines().any(|entry| is_ancestor(&c.synced, entry))
    }

    /// Merging <target> into the rebuild from <base> gives exactly <target>'s
    /// files, without a conflict.
    fn merge_gives(&self, base: &str, target: &str) -> bool {
        let merged = git(&[
            "merge-tree",
            "--write-tree",
            &format!("--merge-base={base}"),
            &self.c.rebuilt,
            target,
        ])
        .q()
        .out();
        merged.is_some_and(|merged| merged.lines().next().map(str::to_string) == tree_of(target))
    }

    /// Where the fetched upstream branch was before a rewrite took the
    /// rebuild's commits out of it: its fork point, the newest commit the
    /// branch's reflog has that the rebuild has too, if the branch doesn't have
    /// it any more. Nothing without a rewrite, without a reflog, or with
    /// --no-fork-point.
    fn fork_point(&self) -> Option<String> {
        if self.merge_no_fork_point {
            return None;
        }
        let fork = git(&[
            "merge-base",
            "--fork-point",
            &self.c.target_ref,
            &self.c.rebuilt,
        ])
        .q()
        .out()?;
        (!is_ancestor(&fork, &self.c.target_ref)).then_some(fork)
    }

    /// For a splice that's up to date: records the upstream branch as the
    /// synced commit, in a commit that only changes the state file, if the
    /// folder already has its files but it isn't part of the rebuild's history.
    /// That happens when the upstream rewrote its history to the same files,
    /// squash-merged what this branch pushed, or got the rebuild edited before
    /// the push. Without the record, the rebuild would keep the monorepo's
    /// original commits, and publish them with the next push.
    fn record_equal_tree(&mut self, path: &str, verb: &str) -> Res<()> {
        let target = commit_of(&self.c.target_ref).unwrap_or_default();
        if self.equal_tree_outcome(path, &target)? != EqualTree::Record {
            if self.merge_bump {
                return self.bump_synced(path);
            }
            log_ok(format!("{path}: nothing to {verb}"));
            return Ok(());
        }
        let folder = tree_of(&target).ok_or(Fail::Soft)?;
        let base_blob = state_file_blob("HEAD", path).ok_or(Fail::Soft)?;
        let new_blob = state_blob(path, &[("commit", &target)])?;
        let message =
            self.commit_message(message::DEFAULT, self.message_for(verb, path, &target))?;
        if splice_in(
            path,
            Some(&folder),
            Some(&base_blob),
            &folder,
            &new_blob,
            &message,
        )
        .is_err()
        {
            return fail(format!("{path}: {verb} failed"));
        }
        log_ok(format!(
            "{path}: recorded {} as the synced commit -- the folder already has its files",
            short(&target)
        ));
        Ok(())
    }

    /// For --bump: records the upstream branch as the synced commit, in a commit
    /// that only changes the state file, though it's already part of the
    /// rebuild's history. Never moves the synced commit backwards.
    fn bump_synced(&mut self, path: &str) -> Res<()> {
        let target = commit_of(&self.c.target_ref).unwrap_or_default();
        if target == self.c.synced {
            log_ok(format!(
                "{path}: nothing to bump -- already synced at {}",
                short(&target)
            ));
            return Ok(());
        }
        if !newer_than_synced(&self.c.synced, &target) {
            log_ok(format!(
                "{path}: nothing to bump -- the fetched '{}' is older than the synced commit",
                self.c.upstream_label
            ));
            return Ok(());
        }
        let folder = git(&["rev-parse", &format!("HEAD:{path}")])
            .out()
            .ok_or(Fail::Soft)?;
        let base_blob = state_file_blob("HEAD", path).ok_or(Fail::Soft)?;
        let new_blob = state_blob(path, &[("commit", &target)])?;
        let message =
            self.commit_message(message::DEFAULT, self.message_for("bump", path, &target))?;
        if splice_in(
            path,
            Some(&folder),
            Some(&base_blob),
            &folder,
            &new_blob,
            &message,
        )
        .is_err()
        {
            return fail(format!("{path}: bump failed"));
        }
        log_ok(format!(
            "{path}: bumped the synced commit to {}",
            short(&target)
        ));
        Ok(())
    }

    /// The tag or commit the default-pin of the splice's upstream in use names
    /// is here, or it has none.
    fn pin_here(&self, path: &str) -> bool {
        let pin = upstream_config(path, &self.name_of(path), "default-pin");
        if pin.is_empty() {
            true
        } else if is_commit_id(&pin) {
            commit_here(&pin)
        } else {
            let key = self.key_of(path);
            ref_exists(&format!(
                "refs/splices/{}/tags/{pin}",
                if key.is_empty() { "." } else { &key }
            ))
        }
    }

    /// Reads the splice's upstreams again after a merge above changed its
    /// .splice, and uses the one the command chose, if it merges the splice:
    /// <upstream> is None for one it only fetches. A pull fetches the upstreams
    /// it names now, but didn't before: the synced commit the merge above moved
    /// it to may be in any of them. It also fetches the one it uses, or all of
    /// them for one it doesn't merge, if that synced commit or the pin isn't
    /// here. Fails, saying why, if one can't be fetched, if the synced commit is
    /// on none of them, or if a merge would use one that wasn't.
    fn reload_splice_upstream(
        &mut self,
        path: &str,
        branch: &str,
        verb: &str,
        upstream: Option<&str>,
    ) -> Res<()> {
        let old_urls: Vec<String> = self
            .upstream_lists
            .get(path)
            .cloned()
            .unwrap_or_default()
            .iter()
            .map(|name| self.url_of(path, name))
            .collect();
        contained(self.load_splice_upstream(path))?;
        if let Some(upstream) = upstream {
            contained(self.use_upstreams(upstream, &[path.to_string()]))?;
        }
        let mut entries = Vec::new();
        let mut used_is_new = false;
        for name in self.upstream_lists[path].clone() {
            if !old_urls.contains(&self.url_of(path, &name)) {
                if name == self.name_of(path) {
                    used_is_new = true;
                }
                entries.push((path.to_string(), name));
            }
        }
        // A new upstream may lack them, and the one in use have them.
        if !synced_commit_here(path) || !self.pin_here(path) {
            let more = if upstream.is_some() {
                used_is_new = true;
                vec![(path.to_string(), self.name_of(path))]
            } else {
                self.every_upstream_entry(&[path.to_string()])?
            };
            for entry in more {
                if !entries.contains(&entry) {
                    entries.push(entry);
                }
            }
        }
        if entries.is_empty() {
            return Ok(());
        }
        if verb == "pull" {
            if !self.fetch_all(branch, &entries)?.is_empty() {
                return Err(Fail::Soft);
            }
            // A fetch by hash fails quietly when no upstream has the commit
            // any more, e.g. after a gc.
            if !synced_commit_here(path) {
                let synced = splice_config(path, "commit", "HEAD");
                return fail(format!(
                    "{path}: its synced commit {}, from a pull above, isn't on its upstream any more",
                    short(&synced)
                ));
            }
        } else if used_is_new && (!self.splice_fetched(path) || !synced_commit_here(path)) {
            log_warn(format!(
                "{path}: not fetched yet -- run 'git splice fetch {}{path}' first",
                self.upstream_option(path)
            ));
            return Err(Fail::Soft);
        }
        Ok(())
    }

    /// Merges every given path, stopping at the first one that leaves a
    /// conflict: another cherry-pick can't start before it's resolved. Top-down:
    /// a splice goes before the ones below it, whose .splice its merge may
    /// change, and a failure stops them. Fails if anything was skipped or failed.
    pub fn merge_paths(&mut self, branch: &str, verb: &str, given: &[String]) -> Res<()> {
        let mut paths = splices_in_order(false, given);
        // pull --all reaches the splices below each through the one above.
        let recursive = self.args.has_flag("--recursive") || (verb == "pull" && self.args.all);
        let state_file_here = |path: &str| {
            git(&["cat-file", "-e", &format!("HEAD:{path}/{STATE_FILE}")])
                .q()
                .ok()
        };
        let track = self.args.has_flag("--track");
        let wanted = self.args.branch.clone();
        // Each .splice below a merged splice, as last loaded: as in HEAD
        // before the first merge, until a merge above changes it.
        let before = git(&["rev-parse", "HEAD"]).out().unwrap_or_default();
        let mut loaded: HashMap<String, Option<String>> = HashMap::new();
        let mut failures: Vec<String> = Vec::new();
        let mut skipped: Vec<String> = Vec::new();
        let mut next = 0;
        while next < paths.len() {
            let path = &paths[next].clone();
            next += 1;
            if splice_in_progress() {
                skipped.push(path.clone());
                continue;
            }
            // Reading its .splice again after a merge above failed, e.g. the
            // fetch of the upstream it names now; the reason came then.
            if failures.contains(path) {
                log_err(format!(
                    "{path}: not {}, since its {STATE_FILE} from a merge above failed to load",
                    past_tense(verb)
                ));
                continue;
            }
            if let Some(failed) = first_above(path, &failures) {
                log_err(format!(
                    "{path}: not {}, since {failed} above it failed",
                    past_tense(verb)
                ));
                failures.push(path.clone());
                continue;
            }
            // Its merge could change the .splice of the failed one again: then
            // that one's failure would be about a file that's gone.
            if let Some(failed) = first_below(path, &failures) {
                log_err(format!(
                    "{path}: not {}, since {failed} below it failed",
                    past_tense(verb)
                ));
                failures.push(path.clone());
                continue;
            }
            // A pull of a splice above this one may have removed it.
            if !state_file_here(path) {
                let named = self.args.paths.iter().any(|p| normalize_path(p) == *path);
                match first_above(path, &paths) {
                    Some(above) if recursive && !named => {
                        log_ok(format!("{path}: removed by the {verb} of {above}"));
                    }
                    _ => log_ok(format!(
                        "{path}: not a splice any more -- nothing to {verb}"
                    )),
                }
                continue;
            }
            // A copy of a splice it's inside, by its id: pulling it brings in
            // another copy below, and that one the next, so recursion ends.
            let named = self.args.paths.iter().any(|p| normalize_path(p) == *path);
            let id = splice_config(path, "id", "HEAD");
            if recursive && !named && !id.is_empty() {
                let copied = self
                    .all_paths
                    .iter()
                    .filter(|above| path.starts_with(&format!("{above}/")))
                    .find(|above| splice_config(above, "id", "HEAD") == id);
                if let Some(above) = copied {
                    log_ok(format!(
                        "{path}: a copy of {above}, which it's inside -- not {}",
                        past_tense(verb)
                    ));
                    continue;
                }
            }
            match self.merge_one(path, branch, verb) {
                Err(Fail::Hard) => return Err(Fail::Hard),
                Err(_) => failures.push(path.clone()),
                Ok(()) => {
                    if track && !splice_in_progress() {
                        match self.track_branch(path, branch, &wanted) {
                            Err(Fail::Hard) => return Err(Fail::Hard),
                            Err(_) => failures.push(path.clone()),
                            Ok(()) => {}
                        }
                    }
                }
            }
            // The splices below a failed one are skipped anyway.
            if !splice_in_progress() && !failures.contains(path) {
                // A splice its pull added is known from now on, so the
                // reading below fetches it; a recursive pull pulls it too.
                let added = if recursive || verb == "pull" {
                    self.discover_below(path)?
                } else {
                    Vec::new()
                };
                if recursive {
                    for added in added {
                        // Below a selected splice, as the ones found before
                        // the pull: --branch names its upstream branch too.
                        if self.selected.contains(path) && !self.selected.contains(&added) {
                            self.selected.push(added.clone());
                        }
                        let at = paths
                            .iter()
                            .rposition(|known| added.starts_with(&format!("{known}/")))
                            .map_or(paths.len(), |above| above + 1);
                        paths.insert(at.max(next), added);
                    }
                }
                self.read_below_again(
                    path,
                    branch,
                    verb,
                    &paths,
                    (&before, &mut loaded),
                    &mut failures,
                )?;
            }
        }
        if !skipped.is_empty() {
            let conclude = if rebase_in_progress() {
                "git rebase --continue"
            } else {
                "git commit"
            };
            log_err(format!(
                "Not {} yet: {} -- resolve the conflict, run '{conclude}', then re-run {verb}",
                past_tense(verb),
                skipped.join(" ")
            ));
        }
        if !failures.is_empty() {
            log_err(format!("Failed: {}", failures.join(" ")));
        }
        if skipped.is_empty() && failures.is_empty() {
            Ok(())
        } else {
            Err(Fail::Hard)
        }
    }

    /// After a merge of <merged>: each splice below it reads its .splice again
    /// where the merge changed it, as in the commit of the splice above, the
    /// layer it syncs with. Selected or not: a splice further down follows the
    /// upstreams of the ones above it. A pull fetches what the new .splice
    /// names; see reload_splice_upstream. A splice that fails that fails the
    /// command, and stops the ones below it. A merge only reads the .splice of
    /// one it doesn't merge itself.
    fn read_below_again(
        &mut self,
        merged: &str,
        branch: &str,
        verb: &str,
        selected: &[String],
        (before, loaded): (&str, &mut HashMap<String, Option<String>>),
        failures: &mut Vec<String>,
    ) -> Res<()> {
        let prefix = format!("{merged}/");
        for path in splices_in_order(false, &self.all_paths.clone()) {
            if !path.starts_with(&prefix) || first_above(&path, failures).is_some() {
                continue;
            }
            let blob = state_file_blob("HEAD", &path);
            let last = loaded
                .entry(path.clone())
                .or_insert_with(|| state_file_blob(before, &path));
            if blob.is_none() || *last == blob {
                continue;
            }
            loaded.insert(path.clone(), blob);
            // --upstream names one of the selected splice's upstreams.
            let upstream = if selected.contains(&path) {
                Some(self.args.upstream.clone())
            } else if verb == "merge" {
                // Nothing to fetch, and nothing of its own to merge: only the
                // upstreams the splices below it follow.
                if contained(self.load_splice_upstream(&path)).is_err() {
                    failures.push(path);
                }
                continue;
            } else {
                None
            };
            match self.reload_splice_upstream(&path, branch, verb, upstream.as_deref()) {
                Err(Fail::Hard) => return Err(Fail::Hard),
                Err(_) => failures.push(path),
                Ok(()) => {}
            }
        }
        Ok(())
    }
}

/// The splice's synced commit is here, or it has none.
pub fn synced_commit_here(path: &str) -> bool {
    let synced = splice_config(path, "commit", "HEAD");
    synced.is_empty() || commit_here(&synced)
}

/// Refuses the first submodule upstream commit <target> adds, or moves to
/// another commit, since upstream commit <base>. One it leaves alone merges
/// cleanly: the monorepo's side keeps what it has there.
fn refuse_changed_submodule(path: &str, base: &str, target: &str) -> Res<()> {
    let changes = git(&["diff-tree", "-r", "--no-renames", base, target])
        .out()
        .unwrap_or_default();
    let inner = changes.lines().find_map(|line| {
        let (fields, file) = line.split_once('\t')?;
        (fields.split(' ').nth(1) == Some("160000")).then_some(file)
    });
    if let Some(inner) = inner {
        return fail(format!(
            "{path}: upstream has a submodule, {inner}, which nobody could check out in the monorepo -- turn it into a splice in the upstream first"
        ));
    }
    Ok(())
}

/// The options merge and pull share, on the repository.
pub fn apply_merge_options(repo: &mut Repo) -> Res<()> {
    repo.joins_rewritten = true;
    repo.merge_bump = repo.args.has_flag("--bump");
    repo.merge_no_fork_point = repo.args.has_flag("--no-fork-point");
    repo.merge_rebase = repo.args.has_flag("--rebase");
    if repo.merge_bump && repo.merge_rebase {
        return die("--bump and --rebase don't go together");
    }
    Ok(())
}

pub const MERGE_OPTIONS: &str =
    "--upstream --branch --track --bump --rebase --no-fork-point -m --message-template";

impl Repo {
    /// For --rebuilt-commit: merges <commit>, which continues the splice's
    /// rebuild, e.g. with a pull made in a worktree of it, into the folder.
    /// A three-way merge from where <commit> left the rebuild, as one
    /// ordinary commit. The synced commit stays: <commit> isn't upstream's.
    fn merge_rebuilt_commit(&mut self, path: &str, commit: &str) -> Res<()> {
        let Some(given) = commit_of(commit) else {
            return die(format!("--rebuilt-commit: unknown commit: {commit}"));
        };
        let Some(rebuilt) = self.rebuild_splice(path, "HEAD")? else {
            return die(format!(
                "{path}: no rebuild to continue, e.g. before its first fetch -- run 'git splice fetch {}' first",
                shell_quote(path)
            ));
        };
        let Some(base) = git(&["merge-base", &rebuilt, &given]).out() else {
            return die(format!(
                "{path}: {} shares no history with its rebuild -- --rebuilt-commit takes a commit made on top of 'git splice rebuild {}'",
                short(&given),
                shell_quote(path)
            ));
        };
        if base == given {
            log_ok(format!(
                "{path}: {} is part of the rebuild already -- nothing to merge",
                short(&given)
            ));
            return Ok(());
        }
        if upstream_has_state_file(&given) {
            return die(format!(
                "{path}: {} has a {STATE_FILE} at its root, which would replace {path}/{STATE_FILE}",
                short(&given)
            ));
        }
        refuse_changed_submodule(path, &base, &given)?;
        self.refuse_upstream_commits(path, &rebuilt, &given)?;
        let count = git(&["rev-list", "--count", &format!("{base}..{given}")])
            .out()
            .unwrap_or_default();
        let default = if count == "1" {
            git(&["log", "-1", "--format=%B", &given])
                .out()
                .unwrap_or_default()
        } else {
            format!("splice: merge {} into {path}", short(&given))
        };
        let message = self.given_message_or(default);
        let blob = state_file_blob("HEAD", path).ok_or(Fail::Hard)?;
        let base_folder = tree_of(&base).ok_or(Fail::Hard)?;
        match splice_in(
            path,
            Some(&base_folder),
            Some(&blob),
            &format!("{given}^{{tree}}"),
            &blob,
            &message,
        ) {
            Err(_) => return die(format!("{path}: merge failed")),
            Ok(false) => {
                log_ok(format!(
                    "{path}: {}'s changes are in the folder already -- nothing to merge",
                    short(&given)
                ));
                return Ok(());
            }
            Ok(true) => {}
        }
        log_ok(format!("{path}: merged {}", short(&given)));
        Ok(())
    }
}

impl Repo {
    /// --rebuilt-commit merges <commit> as the monorepo's own work and keeps
    /// the synced commit. A commit of the splice's upstream in <commit> that
    /// the rebuild lacks, e.g. from a pull in a worktree of it, would come in
    /// as local work too, and the next push would publish its changes again,
    /// in a commit of its own. A pull records it as the synced commit instead.
    fn refuse_upstream_commits(&mut self, path: &str, rebuilt: &str, given: &str) -> Res<()> {
        self.require_upstream_list(path)?;
        let names = self.upstream_lists.get(path).cloned().unwrap_or_default();
        let mut prefixes = Vec::new();
        for name in names {
            let url = self.url_of(path, &name);
            let key = self.upstream_key(&url)?;
            if !key.is_empty() {
                prefixes.push(format!("refs/splices/{key}/"));
            }
        }
        if prefixes.is_empty() {
            return Ok(());
        }
        let local = git(&["rev-list", given, "--not", rebuilt])
            .out()
            .unwrap_or_default();
        for commit in local.lines() {
            let mut args = vec![
                "for-each-ref",
                "--count=1",
                "--format=%(refname)",
                "--contains",
                commit,
            ];
            args.extend(prefixes.iter().map(String::as_str));
            if git(&args).out().is_some_and(|found| !found.is_empty()) {
                return die(format!(
                    "{path}: {} has {}, a commit of its upstream that the rebuild lacks, which would come in as a local change -- 'git splice pull {}' takes the upstream's commits in instead",
                    short(given),
                    short(commit),
                    shell_quote(path)
                ));
            }
        }
        Ok(())
    }
}

pub fn run(argv: &[String]) -> Res<i32> {
    let args = parse_args(USAGE, &format!("{MERGE_OPTIONS} --rebuilt-commit"), argv)?;
    args.require_one_splice_for_message()?;
    args.require_branch_for_track()?;
    let rebuilt_commit = args.rebuilt_commit.clone();
    if !rebuilt_commit.is_empty() && !args.message_template.is_empty() {
        return die(
            "--rebuilt-commit keeps the message of the commit it merges -- -m replaces it, --message-template doesn't go with it",
        );
    }
    if !rebuilt_commit.is_empty() {
        let given = [
            ("--upstream", !args.upstream.is_empty()),
            ("--branch", !args.branch.is_empty()),
            ("--track", args.has_flag("--track")),
            ("--bump", args.has_flag("--bump")),
            ("--rebase", args.has_flag("--rebase")),
            ("--no-fork-point", args.has_flag("--no-fork-point")),
        ];
        if let Some((option, _)) = given.into_iter().find(|(_, given)| *given) {
            return die(format!(
                "--rebuilt-commit merges the given commit, not an upstream branch -- {option} doesn't go with it"
            ));
        }
    }
    let mut repo = Repo::new(args);
    apply_merge_options(&mut repo)?;
    repo.open()?;
    // Before select_splices: a rebase in progress has detached HEAD.
    require_no_splice_in_progress()?;
    if !rebuilt_commit.is_empty() {
        // No upstream to choose: the commit is given, and the check for
        // upstream commits in it reads every upstream the splice names.
        repo.select_paths(Kind::Explicit, "merge")?;
        if repo.args.all || repo.selected.len() != 1 {
            return die("--rebuilt-commit takes exactly one splice");
        }
        let path = repo.selected[0].clone();
        repo.merge_rebuilt_commit(&path, &rebuilt_commit)?;
        return Ok(0);
    }
    repo.require_message_template(Message {
        command: "merge",
        upstream: KNOWN,
        old: KNOWN,
        new: KNOWN,
        ..Message::default()
    })?;
    repo.select_splices(Kind::Explicit, "merge")?;
    let branch = repo.monorepo_branch.clone();
    let selected = repo.selected.clone();
    repo.merge_paths(&branch, "merge", &selected)?;
    Ok(0)
}
