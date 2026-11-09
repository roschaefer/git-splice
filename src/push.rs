//! git splice push.

use crate::args::parse_args;
use crate::context::ExecutionContext;
use crate::merge::EqualTree;
use crate::repo::*;
use crate::util::*;

pub const USAGE: &str = include_str!("usage/push.txt");

impl Repo<'_> {
    /// Prepares one splice's push.
    fn prepare_push(&mut self, path: &str, branch: &str, force: bool) -> Res<Option<PreparedPush>> {
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
                self.remind_pull(path, &selection)?;
                return Ok(None);
            }
            State::Pull if !force => {
                log_ok(format!(
                    "{path}: nothing to push (upstream is ahead -- 'git splice pull {selection}{path}' brings it in)"
                ));
                return Ok(None);
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
                    && !self.context.supplied_rebuilds.contains_key(path)
                    && self.d.no_changes
                {
                    log_ok(format!(
                        "{path}: nothing to push (upstream has no '{label}' branch, and a PR to '{}' would show no changes)",
                        self.d.default_branch
                    ));
                    return Ok(None);
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
            return Ok(None);
        }

        let url = self.url_in_use(path);
        // Before the push, so a failure to record the key can't follow a push
        // that already happened.
        self.ensure_splice_key(path)?;
        Ok(Some(PreparedPush {
            path: path.to_string(),
            upstream: self.name_of(path),
            url,
            branch: c.upstream_branch,
            label,
            old: commit_of(&c.target_ref),
            synced: c.synced,
            rebuilt_commit: rebuilt,
        }))
    }

    fn publish_push(&mut self, push: &PreparedPush, force: bool) -> Res<()> {
        let path = &push.path;
        let rebuilt = &push.rebuilt_commit;
        let url = &push.url;
        let label = &push.label;
        let option = self.upstream_option(path);
        let selection = self.selection_options(path);
        let refspec = format!("{rebuilt}:refs/heads/{}", push.branch);
        let mut args = vec!["push"];
        if force {
            args.push("--force");
        }
        args.extend_from_slice(&["--quiet", "--", url, &refspec]);
        if git(&args).run() != 0 {
            return fail(format!("{path}: push failed"));
        }
        // Pushing to a URL updates no ref here, so record what upstream has now.
        let fetched = self.splice_ref(path, &push.branch);
        if !git(&["update-ref", "--create-reflog", &fetched, rebuilt]).ok() {
            return fail(format!(
                "{path}: pushed, but couldn't record it in {fetched} -- run 'git splice fetch {option}{path}'"
            ));
        }
        log_ok(format!("{path}: pushed {} to {label}", short(rebuilt)));
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
        let Some(given) = self.context.supplied_rebuilds.get(path).cloned() else {
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
    pub(crate) fn give_rebuild(&mut self, path: &str, commit: &str, force: bool) -> Res<()> {
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
        self.context
            .supplied_rebuilds
            .insert(path.to_string(), rebuilt);
        Ok(())
    }
}

pub fn run(context: &mut ExecutionContext, argv: &[String]) -> Res<i32> {
    let args = parse_args(
        USAGE,
        "--force --upstream --branch --track --rebuilt-commit --exec --continue-from",
        argv,
    )?;
    args.require_branch_for_track()?;
    if !args.exec.is_empty() || !args.continue_from.is_empty() {
        return crate::checkpoint::run(context, "push", args);
    }
    let mut repo = Repo::new(context, args);
    repo.open()?;
    let mut progress = PushProgress::new(&mut repo)?;
    let branch = repo.monorepo_branch.clone();
    while !progress.done() {
        progress.advance(&mut repo, &branch)?;
    }
    progress.finish()
}

#[derive(Clone, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct PreparedPush {
    pub path: String,
    pub upstream: String,
    pub url: String,
    pub branch: String,
    pub label: String,
    pub old: Option<String>,
    pub synced: String,
    pub rebuilt_commit: String,
}

#[derive(Clone, Default, serde::Serialize, serde::Deserialize)]
#[serde(tag = "step", rename_all = "kebab-case", deny_unknown_fields)]
enum PushPhase {
    #[default]
    Rebuild,
    Publish {
        prepared: PreparedPush,
    },
    Done,
}

#[derive(Clone, Default, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct PushProgress {
    paths: Vec<String>,
    next: usize,
    failures: Vec<String>,
    given: std::collections::HashMap<String, String>,
    phase: PushPhase,
}

impl PushProgress {
    pub fn new(repo: &mut Repo) -> Res<Self> {
        repo.select_splices(Kind::Explicit, "push")?;
        let commit = repo.args.rebuilt_commit.clone();
        if !commit.is_empty() {
            if repo.args.all || repo.selected.len() != 1 {
                return die("--rebuilt-commit takes exactly one splice");
            }
            let path = repo.selected[0].clone();
            repo.give_rebuild(&path, &commit, repo.args.has_flag("--force"))?;
        }
        let selected = repo.selected.clone();
        repo.load_uncommitted_changes(&selected);
        Ok(Self {
            paths: splices_in_order(true, &selected),
            given: repo.context.supplied_rebuilds.clone(),
            ..Self::default()
        })
    }

    pub fn done(&self) -> bool {
        matches!(self.phase, PushPhase::Done)
    }

    pub fn remaining(&self) -> &[String] {
        let next = if matches!(self.phase, PushPhase::Publish { .. }) {
            self.next.saturating_sub(1)
        } else {
            self.next
        };
        &self.paths[next.min(self.paths.len())..]
    }

    pub fn replace_rebuild(&mut self, repo: &mut Repo, commit: &str) -> Res<()> {
        if repo.args.all || self.paths.len() != 1 {
            return die("rebuilt_commit result takes exactly one explicitly named splice, as --rebuilt-commit does");
        }
        let PushPhase::Publish { prepared } = &mut self.phase else {
            return die("rebuilt_commit result requires an after-rebuild checkpoint");
        };
        repo.context.supplied_rebuilds = self.given.clone();
        repo.give_rebuild(&prepared.path, commit, repo.args.has_flag("--force"))?;
        prepared.rebuilt_commit = repo.context.supplied_rebuilds[&prepared.path].clone();
        self.given = repo.context.supplied_rebuilds.clone();
        Ok(())
    }

    fn track(&mut self, repo: &mut Repo, path: &str, branch: &str) -> Res<()> {
        if !repo.args.has_flag("--track") {
            return Ok(());
        }
        let wanted = repo.args.branch.clone();
        let reference = repo.splice_ref(path, &wanted);
        if !ref_exists(&reference) {
            log_err(format!(
                "{path}: upstream has no '{wanted}' branch to track -- the push didn't create it"
            ));
            self.failures.push(path.to_string());
        } else {
            match repo.track_branch(path, branch, &wanted) {
                Err(Fail::Hard) => return Err(Fail::Hard),
                Err(_) => self.failures.push(path.to_string()),
                Ok(()) => {}
            }
        }
        Ok(())
    }

    pub fn advance(
        &mut self,
        repo: &mut Repo,
        branch: &str,
    ) -> Res<Option<crate::checkpoint::Event>> {
        use crate::checkpoint::Event;
        repo.context.supplied_rebuilds = self.given.clone();
        let force = repo.args.has_flag("--force");
        match self.phase.clone() {
            PushPhase::Done => Ok(None),
            PushPhase::Rebuild => {
                if self.next >= self.paths.len() {
                    self.phase = PushPhase::Done;
                    return Ok(None);
                }
                let path = self.paths[self.next].clone();
                self.next += 1;
                if let Some(failed) = first_below(&path, &self.failures) {
                    log_err(format!(
                        "{path}: not pushed, since {failed} below it failed"
                    ));
                    self.failures.push(path);
                    return Ok(None);
                }
                match repo.prepare_push(&path, branch, force) {
                    Err(Fail::Hard) => Err(Fail::Hard),
                    Err(_) => {
                        self.failures.push(path);
                        Ok(None)
                    }
                    Ok(None) => {
                        self.track(repo, &path, branch)?;
                        Ok(None)
                    }
                    Ok(Some(prepared)) => {
                        self.phase = PushPhase::Publish {
                            prepared: prepared.clone(),
                        };
                        Ok((!repo.args.exec.is_empty()).then_some(Event::AfterRebuild(prepared)))
                    }
                }
            }
            PushPhase::Publish { prepared } => {
                self.phase = PushPhase::Rebuild;
                if !repo.args.exec.is_empty()
                    && (commit_of(&prepared.rebuilt_commit).as_deref()
                        != Some(prepared.rebuilt_commit.as_str())
                        || tree_of(&prepared.rebuilt_commit)
                            != repo.content_tree("HEAD", &prepared.path)?)
                {
                    return die("prepared push no longer matches the committed splice content");
                }
                match repo.publish_push(&prepared, force) {
                    Err(Fail::Hard) => Err(Fail::Hard),
                    Err(_) => {
                        self.failures.push(prepared.path);
                        Ok(None)
                    }
                    Ok(()) => {
                        self.track(repo, &prepared.path, branch)?;
                        Ok((!repo.args.exec.is_empty()).then_some(Event::AfterPush(prepared)))
                    }
                }
            }
        }
    }

    pub fn finish(&self) -> Res<i32> {
        if self.failures.is_empty() {
            Ok(0)
        } else {
            log_err(format!("Failed: {}", self.failures.join(" ")));
            Ok(1)
        }
    }
}
