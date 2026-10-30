//! git splice merge.

use crate::args::parse_args;
use crate::repo::*;
use crate::state::*;
use crate::util::*;

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

fn state_file_blob(path: &str) -> Option<String> {
    git(&["rev-parse", &format!("HEAD:{path}/{STATE_FILE}")]).out()
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
        let base_blob = state_file_blob(path).ok_or(Fail::Soft)?;
        let new_blob = state_blob(path, &[("commit", &target)])?;
        let message = self.commit_message(format!(
            "splice: {verb} {path} from {label} at {}",
            short(&target)
        ));
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
        if self.lacks_synced_by_reflog() {
            return fail(format!(
                "{path}: '{}' lacks the synced commit {}, and its reflog here doesn't show it ever had it -- --rebase would drop that commit's changes",
                c.upstream_label,
                short(&c.synced)
            ));
        }
        let synced_tree = tree_of(&c.synced);
        let mut base = None;
        let history = git(&["rev-list", "--first-parent", "HEAD"])
            .out()
            .unwrap_or_default();
        for commit in history.lines() {
            if splice_config(path, "commit", commit) != c.synced {
                break;
            }
            if self.content_tree(commit, path)? == synced_tree {
                base = Some(commit.to_string());
                break;
            }
        }
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
        let message = self.commit_message(format!(
            "splice: {verb} {path} from {} at {}",
            c.upstream_label,
            short(&target)
        ));
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
        let base_blob = state_file_blob(path).ok_or(Fail::Soft)?;
        let new_blob = state_blob(path, &[("commit", &target)])?;
        let message = self.commit_message(format!(
            "splice: {verb} {path} from {} at {}",
            self.c.upstream_label,
            short(&target)
        ));
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
        let base_blob = state_file_blob(path).ok_or(Fail::Soft)?;
        let new_blob = state_blob(path, &[("commit", &target)])?;
        let message = self.commit_message(format!(
            "splice: bump {path} from {} at {}",
            self.c.upstream_label,
            short(&target)
        ));
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
    /// .splice, and uses the one the command chose. A pull fetches the upstreams
    /// it names now, but didn't before: the synced commit the merge above moved
    /// it to may be in any of them. It also fetches the one it uses if that
    /// synced commit or the pin isn't here. Fails, saying why, if one can't be
    /// fetched, if the synced commit is on none of them, or if a merge would use
    /// one that wasn't.
    fn reload_splice_upstream(
        &mut self,
        path: &str,
        branch: &str,
        verb: &str,
        upstream: &str,
    ) -> Res<()> {
        let old_urls: Vec<String> = self
            .upstream_lists
            .get(path)
            .cloned()
            .unwrap_or_default()
            .iter()
            .map(|name| self.url_of(path, name))
            .collect();
        self.load_splice_upstream(path)?;
        self.use_upstreams(upstream, &[path.to_string()])?;
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
        if entries.is_empty() && (!synced_commit_here(path) || !self.pin_here(path)) {
            entries.push((path.to_string(), self.name_of(path)));
            used_is_new = true;
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
    /// a splice goes before the ones below it, whose synced commit its pull may
    /// move, and a failure stops them. Fails if anything was skipped or failed.
    pub fn merge_paths(&mut self, branch: &str, verb: &str, given: &[String]) -> Res<()> {
        let paths = splices_in_order(false, given);
        let loaded = git(&["rev-parse", "HEAD"]).out().unwrap_or_default();
        let unchanged_since_loaded = |path: &str| {
            let spec = format!("{path}/{STATE_FILE}");
            git(&["diff", "--quiet", &loaded, "HEAD", "--", &spec]).ok()
        };
        let state_file_here = |path: &str| {
            git(&["cat-file", "-e", &format!("HEAD:{path}/{STATE_FILE}")])
                .q()
                .ok()
        };
        let track = self.args.has_flag("--track");
        let wanted = self.args.branch.clone();
        let upstream = self.args.upstream.clone();
        let mut failures: Vec<String> = Vec::new();
        let mut skipped: Vec<String> = Vec::new();
        for path in &paths {
            if splice_in_progress() {
                skipped.push(path.clone());
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
            // A pull of a splice above this one may have removed it.
            if !state_file_here(path) {
                log_ok(format!(
                    "{path}: not a splice any more -- nothing to {verb}"
                ));
                continue;
            }
            // ... or changed its upstreams, read before it merged.
            if !unchanged_since_loaded(path) {
                match self.reload_splice_upstream(path, branch, verb, &upstream) {
                    Err(Fail::Hard) => return Err(Fail::Hard),
                    Err(_) => {
                        failures.push(path.clone());
                        continue;
                    }
                    Ok(()) => {}
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
        }
        // A pull above may also move the synced commit of a splice below it
        // that isn't pulled itself: fetch that commit too, or the splice would
        // look like it shares no history with its upstream. --upstream names
        // one of the pulled splice's upstreams, so this uses the default one.
        if verb == "pull" && !splice_in_progress() {
            for path in self.all_paths.clone() {
                if paths.contains(&path)
                    || first_above(&path, &paths).is_none()
                    || !state_file_here(&path)
                    || unchanged_since_loaded(&path)
                    || synced_commit_here(&path)
                {
                    continue;
                }
                match self.reload_splice_upstream(&path, branch, "pull", "") {
                    Err(Fail::Hard) => return Err(Fail::Hard),
                    Err(_) => failures.push(path),
                    Ok(()) => {}
                }
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

pub const MERGE_OPTIONS: &str = "--upstream --branch --track --bump --rebase --no-fork-point -m";

pub fn run(argv: &[String]) -> Res<i32> {
    let args = parse_args(USAGE, MERGE_OPTIONS, argv)?;
    args.require_one_splice_for_message()?;
    args.require_branch_for_track()?;
    let mut repo = Repo::new(args);
    apply_merge_options(&mut repo)?;
    repo.open()?;
    // Before select_splices: a rebase in progress has detached HEAD.
    require_no_splice_in_progress()?;
    repo.select_splices(Kind::Explicit, "merge")?;
    let branch = repo.monorepo_branch.clone();
    let selected = repo.selected.clone();
    repo.merge_paths(&branch, "merge", &selected)?;
    Ok(0)
}
