//! git splice push.

use crate::args::parse_args;
use crate::merge::EqualTree;
use crate::repo::*;
use crate::util::*;

pub const USAGE: &str = include_str!("usage/push.txt");

impl Repo {
    /// Pushes one splice.
    fn push_one(&mut self, path: &str, branch: &str, force: bool) -> Res<()> {
        match self.has_uncommitted_changes(path) {
            Uncommitted::Changes => log_warn(format!(
                "{path}: uncommitted changes aren't pushed -- commit them first"
            )),
            Uncommitted::Failed => log_warn(format!(
                "{path}: could not check for uncommitted changes (git status failed) -- only committed ones are pushed"
            )),
            Uncommitted::NoChanges => {}
        }
        self.classify_splice(path, branch)?;
        let c = self.c.clone();
        let label = c.upstream_label.clone();
        let option = self.upstream_option(path);
        let selection = self.selection_options(path);
        if c.target.kind != TargetKind::Branch {
            return fail(format!(
                "{path}: pinned at {} -- a {} isn't pushed to: push from a feature branch, or follow a branch again: git config --file {} --unset upstream.{}.default-pin",
                c.target.description(),
                c.target.kind_name(),
                shell_quote(&format!("{path}/{STATE_FILE}")),
                self.name_of(path)
            ));
        }
        let mut rebuilt = c.rebuilt.clone();
        match c.state {
            State::NeverFetched => {
                log_warn(format!(
                    "{path}: not fetched -- run 'git splice fetch {option}{path}' first"
                ));
                return Err(Fail::Soft);
            }
            State::UpToDate => {
                log_ok(format!("{path}: nothing to push"));
                return self.remind_pull(path, &selection);
            }
            State::Pull if !force => {
                log_ok(format!(
                    "{path}: nothing to push (upstream is ahead -- 'git splice pull {selection}{path}' brings it in)"
                ));
                return Ok(());
            }
            State::Pull => {}
            State::Diverged if !force => {
                return fail(format!("{path}: upstream has commits this branch lacks"));
            }
            State::Diverged => {}
            State::MissingSynced if !force => {
                log_warn(format!("{path}: {}", self.missing_synced_message(path)));
                return Err(Fail::Soft);
            }
            State::MissingSynced => rebuilt = self.rebuild_without_synced(path)?,
            State::UnrelatedHistory if !force => {
                self.print_unrelated_history_guidance(path);
                return Err(Fail::Soft);
            }
            State::UnrelatedHistory => {
                if rebuilt.is_empty() {
                    rebuilt = self.rebuild_without_synced(path)?;
                }
            }
            State::MissingBranch => {
                match self.compare_with_default_branch(path) {
                    Err(Fail::Hard) => return Err(Fail::Hard),
                    Err(_) => {
                        if self.d.default_branch.is_empty() {
                            return fail(format!(
                                "{path}: upstream has no '{label}' branch, and its default branch is unknown -- not creating '{label}'"
                            ));
                        }
                        return fail(format!(
                            "{path}: could not compare with upstream's '{}' -- not creating '{label}'",
                            self.d.default_branch
                        ));
                    }
                    Ok(()) => {}
                }
                rebuilt = self.d.rebuilt.clone();
                // A commit given with --rebuilt-commit is pushed even if
                // upstream's default branch has it: it was asked for, and needs
                // recording.
                if !rebuilt.is_empty()
                    && !self.rebuild_given.contains_key(path)
                    && self.d.no_changes
                {
                    log_ok(format!(
                        "{path}: nothing to push (upstream has no '{label}' branch, and a PR to '{}' would show no changes)",
                        self.d.default_branch
                    ));
                    return Ok(());
                }
                if !rebuilt.is_empty() {
                    log_warn(format!(
                        "{path}: upstream has no '{label}' branch yet -- this push creates it"
                    ));
                }
            }
            State::MissingPin | State::Push => {}
        }

        if rebuilt.is_empty() {
            log_ok(format!("{path}: nothing to push (no content)"));
            return Ok(());
        }

        let url = self.url_in_use(path);
        // Before the push, so a failure to record the key can't follow a push
        // that already happened.
        self.ensure_splice_key(path)?;
        let refspec = format!("{rebuilt}:refs/heads/{}", c.upstream_branch);
        let mut args = vec!["push"];
        if force {
            args.push("--force");
        }
        args.extend_from_slice(&["--quiet", "--", &url, &refspec]);
        if git(&args).run() != 0 {
            return fail(format!("{path}: push failed"));
        }
        // Pushing to a URL updates no ref here, so record what upstream has now.
        let fetched = self.splice_ref(path, &c.upstream_branch);
        if !git(&["update-ref", "--create-reflog", &fetched, &rebuilt]).ok() {
            return fail(format!(
                "{path}: pushed, but couldn't record it in {fetched} -- run 'git splice fetch {option}{path}'"
            ));
        }
        log_ok(format!("{path}: pushed {} to {label}", short(&rebuilt)));
        self.remind_pull(path, &selection)
    }

    /// The rebuild as if the splice had no synced commit: the upstream no
    /// longer has it, and the monorepo's side replaces its history anyway.
    fn rebuild_without_synced(&mut self, path: &str) -> Res<String> {
        self.rebuild_without_synced = true;
        let rebuilt = contained(self.splice_rebuild(path));
        self.rebuild_without_synced = false;
        Ok(rebuilt?.unwrap_or_default())
    }

    /// Reminds to record the commit given for the splice with a pull, if one
    /// was given and the monorepo's rebuild isn't that commit already. Also
    /// after a retry that finds it upstream: the earlier push may have gone
    /// through without its reminder.
    fn remind_pull(&mut self, path: &str, selection: &str) -> Res<()> {
        let Some(given) = self.rebuild_given.get(path).cloned() else {
            return Ok(());
        };
        if !self.given_is_rebuild(path, &given)? {
            log_warn(format!(
                "{path}: run 'git splice pull --bump {selection}{path}' before the next change to it -- that records {} as the synced commit",
                short(&given)
            ));
        }
        Ok(())
    }

    /// The commit given is the monorepo's own rebuild, which needs no record.
    /// Any other, even an ancestor of the rebuild with the same files, leaves
    /// the rebuild with commits the upstream doesn't have. Without the synced
    /// commit here, there's no rebuild to compare with.
    fn given_is_rebuild(&mut self, path: &str, given: &str) -> Res<bool> {
        let synced = splice_config(path, "commit", "HEAD");
        if !synced.is_empty() && !commit_here(&synced) {
            return Ok(false);
        }
        let own = self.rebuild_splice(path, "HEAD").map_err(|_| Fail::Hard)?;
        Ok(own.as_deref() == Some(given))
    }

    /// Records <commit> as the rebuild push sends for the splice, after checking
    /// that it differs from the rebuild only in its history: the same files as
    /// the folder in HEAD, on top of the synced commit -- unless forced, which
    /// may replace the published history too. An upstream that has moved on is
    /// left to the push to reject.
    fn give_rebuild(&mut self, path: &str, commit: &str, force: bool) -> Res<()> {
        let Some(rebuilt) = commit_of(commit) else {
            return die(format!("--rebuilt-commit: unknown commit: {commit}"));
        };
        let folder = self.content_tree("HEAD", path).map_err(|_| Fail::Hard)?;
        if tree_of(&rebuilt) != folder {
            return die(format!(
                "{path}: {} has other files than the folder -- --rebuilt-commit only takes edits to the history; commit changes to files in the monorepo",
                short(&rebuilt)
            ));
        }
        let synced = splice_config(path, "commit", "HEAD");
        // The monorepo's own rebuild needs no record, even where it's the
        // synced commit, e.g. with an upstream that's ahead.
        let outcome = self
            .equal_tree_outcome(path, &rebuilt)
            .map_err(|_| Fail::Hard)?;
        if outcome == EqualTree::Keep {
            let own = self.rebuild_splice(path, "HEAD").map_err(|_| Fail::Hard)?;
            if own.as_deref() != Some(rebuilt.as_str()) {
                return die(format!(
                    "{path}: pull can't record {} as the synced commit -- it isn't newer than {}, so the next push would publish the rebuild's commits after it again",
                    short(&rebuilt),
                    short(&synced)
                ));
            }
        }
        if !synced.is_empty() && !force {
            if !commit_here(&synced) {
                return die(format!(
                    "{path}: synced commit {} isn't available locally -- run 'git splice fetch {}{path}'",
                    short(&synced),
                    self.upstream_option(path)
                ));
            }
            if !is_ancestor(&synced, &rebuilt) {
                return die(format!(
                    "{path}: {} doesn't contain the synced commit {} -- edit only the commits after it, or replace published ones with --force",
                    short(&rebuilt),
                    short(&synced)
                ));
            }
        }
        self.rebuild_given.insert(path.to_string(), rebuilt);
        Ok(())
    }
}

pub fn run(argv: &[String]) -> Res<i32> {
    let args = parse_args(
        USAGE,
        "--force --upstream --branch --track --rebuilt-commit",
        argv,
    )?;
    args.require_branch_for_track()?;
    let force = args.has_flag("--force");
    let track = args.has_flag("--track");
    let wanted = args.branch.clone();
    let mut repo = Repo::new(args);
    repo.open()?;
    repo.select_splices(Kind::Explicit, "push")?;
    let rebuilt_commit = repo.args.rebuilt_commit.clone();
    if !rebuilt_commit.is_empty() {
        if repo.args.all || repo.selected.len() != 1 {
            return die("--rebuilt-commit takes exactly one splice");
        }
        let path = repo.selected[0].clone();
        repo.give_rebuild(&path, &rebuilt_commit, force)?;
    }
    let branch = repo.monorepo_branch.clone();
    let selected = repo.selected.clone();

    // Pushes to the same host share one SSH connection.
    let control = Temp::new();
    if std::fs::create_dir(&control.path).is_err() {
        return die("can't create a folder for SSH connections");
    }
    let ssh = std::env::var("GIT_SSH_COMMAND").unwrap_or_else(|_| "ssh".to_string());
    std::env::set_var(
        "GIT_SSH_COMMAND",
        format!(
            "{ssh} -o ControlMaster=auto -o ControlPersist=60s -o ControlPath={}/%r@%h:%p",
            control.str()
        ),
    );

    // Bottom-up: a splice's push publishes the .splice files below it, which
    // should point at what their own pushes published.
    let paths = splices_in_order(true, &selected);
    repo.load_uncommitted_changes(&selected);
    let mut failures: Vec<String> = Vec::new();
    for path in &paths {
        if let Some(failed) = first_below(path, &failures) {
            log_err(format!(
                "{path}: not pushed, since {failed} below it failed"
            ));
            failures.push(path.clone());
            continue;
        }
        match repo.push_one(path, &branch, force) {
            Err(Fail::Hard) => return Err(Fail::Hard),
            Err(_) => failures.push(path.clone()),
            Ok(()) if track => {
                // A push with nothing to push, e.g. no changes for a PR, creates
                // no branch, and a missing tracked branch would stop every pull.
                let reference = repo.splice_ref(path, &wanted);
                if !git(&["rev-parse", "--verify", "--quiet", &reference])
                    .q()
                    .ok()
                {
                    log_err(format!(
                        "{path}: upstream has no '{wanted}' branch to track -- the push didn't create it"
                    ));
                    failures.push(path.clone());
                } else {
                    match repo.track_branch(path, &branch, &wanted) {
                        Err(Fail::Hard) => return Err(Fail::Hard),
                        Err(_) => failures.push(path.clone()),
                        Ok(()) => {}
                    }
                }
            }
            Ok(()) => {}
        }
    }
    if !failures.is_empty() {
        log_err(format!("Failed: {}", failures.join(" ")));
        return Ok(1);
    }
    Ok(0)
}
