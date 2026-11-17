//! git splice push.

use crate::args::parse_args;
use crate::context::ExecutionContext;
use crate::execution::{Execution, ExecutionEvent, ExecutionOutcome, Operation};
use crate::merge::EqualTree;
use crate::repo::*;
use crate::util::*;

pub const USAGE: &str = include_str!("usage/push.txt");

struct PreparedPush {
    path: String,
    url: String,
    branch: String,
    label: String,
    rebuilt_commit: String,
    fetched_ref: String,
}

impl Repo<'_> {
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
            url,
            branch: c.upstream_branch.clone(),
            label,
            rebuilt_commit: rebuilt,
            fetched_ref: self.splice_ref(path, &c.upstream_branch),
        }))
    }

    fn publish_push(&mut self, prepared: &PreparedPush, force: bool) -> Res<()> {
        let path = &prepared.path;
        let rebuilt = &prepared.rebuilt_commit;
        let url = &prepared.url;
        let label = &prepared.label;
        let option = self.upstream_option(path);
        let selection = self.selection_options(path);
        let refspec = format!("{rebuilt}:refs/heads/{}", prepared.branch);
        let mut args = vec!["push"];
        if force {
            args.push("--force");
        }
        args.extend_from_slice(&["--quiet", "--", url, &refspec]);
        if git(&args).run() != 0 {
            return fail(format!("{path}: push failed"));
        }
        // Pushing to a URL updates no ref here, so record what upstream has now.
        let fetched = &prepared.fetched_ref;
        if !git(&["update-ref", "--create-reflog", fetched, rebuilt]).ok() {
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
        // The children's rebuilds kept for the records change with it.
        self.child_rebuilds.clear();
        self.rebuild_without_synced = true;
        let rebuilt = contained(self.splice_rebuild(path));
        self.rebuild_without_synced = false;
        self.child_rebuilds.clear();
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
    fn give_rebuild(&mut self, path: &str, commit: &str, force: bool) -> Res<()> {
        let Some(rebuilt) = commit_of(commit) else {
            return die(format!("--rebuilt-commit: unknown commit: {commit}"));
        };
        let given = tree_of(&rebuilt);
        if !self
            .folder_is("HEAD", path, given.as_ref())
            .map_err(|_| Fail::Hard)?
        {
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
    start(context, argv)?.run()
}

/// Starts a push whose progress remains owned by the returned execution.
pub fn start<'context>(
    context: &'context mut ExecutionContext,
    argv: &[String],
) -> Res<PushExecution<'context>> {
    let args = parse_args(
        USAGE,
        "--force --upstream --branch --track --rebuilt-commit --exec",
        argv,
    )?;
    args.require_branch_for_track()?;
    let mut repo = Repo::new(context, args);
    repo.open()?;
    let progress = PushProgress::new(&mut repo)?;
    Ok(PushExecution {
        inner: Execution::new(repo, progress)?,
    })
}

/// A push retained in memory. Continuing never repeats a consumed checkpoint.
pub struct PushExecution<'context> {
    inner: Execution<'context, PushProgress>,
}

impl PushExecution<'_> {
    /// Drives remaining work to completion, including after a pause.
    pub fn run(&mut self) -> Res<i32> {
        self.inner.run()
    }

    /// Pauses at a selected event. Local HEAD, branch, fetched refs and Git
    /// configuration must remain unchanged in the predicate and while paused.
    pub fn run_until(
        &mut self,
        stop: impl FnMut(&ExecutionEvent) -> bool,
    ) -> Res<ExecutionOutcome> {
        self.inner.run_until(stop)
    }
}

enum PushPhase {
    Prepare,
    Publish(PreparedPush),
    Done,
}

struct PushProgress {
    paths: std::collections::VecDeque<String>,
    failures: Vec<String>,
    branch: String,
    force: bool,
    tracked_branch: Option<String>,
    phase: PushPhase,
}

impl PushProgress {
    fn new(repo: &mut Repo) -> Res<Self> {
        repo.select_splices(Kind::Explicit, "push")?;
        let force = repo.args.has_flag("--force");
        let rebuilt_commit = repo.args.rebuilt_commit.clone();
        if !rebuilt_commit.is_empty() {
            if repo.args.all || repo.selected.len() != 1 {
                return die("--rebuilt-commit takes exactly one splice");
            }
            let path = repo.selected[0].clone();
            repo.give_rebuild(&path, &rebuilt_commit, force)?;
        }
        let selected = repo.selected.clone();
        repo.load_uncommitted_changes(&selected);
        Ok(Self {
            paths: splices_in_order(true, &selected).into(),
            failures: Vec::new(),
            branch: repo.monorepo_branch.clone(),
            force,
            tracked_branch: repo
                .args
                .has_flag("--track")
                .then(|| repo.args.branch.clone()),
            phase: PushPhase::Prepare,
        })
    }

    fn done(&self) -> bool {
        matches!(self.phase, PushPhase::Done)
    }

    fn advance(&mut self, repo: &mut Repo) -> Res<Option<ExecutionEvent>> {
        match std::mem::replace(&mut self.phase, PushPhase::Done) {
            PushPhase::Done => Ok(None),
            PushPhase::Prepare => {
                let Some(path) = self.paths.pop_front() else {
                    return Ok(None);
                };
                self.phase = PushPhase::Prepare;
                if let Some(failed) = first_below(&path, &self.failures) {
                    log_err(format!(
                        "{path}: not pushed, since {failed} below it failed"
                    ));
                    self.failures.push(path);
                    return Ok(None);
                }
                match repo.prepare_push(&path, &self.branch, self.force) {
                    Err(Fail::Hard) => Err(Fail::Hard),
                    Err(_) => {
                        self.failures.push(path);
                        Ok(None)
                    }
                    Ok(None) => self.track(repo, &path).map(|()| None),
                    Ok(Some(prepared)) => {
                        let event = ExecutionEvent::AfterRebuild {
                            path: prepared.path.clone(),
                            commit: prepared.rebuilt_commit.clone(),
                        };
                        self.phase = PushPhase::Publish(prepared);
                        Ok(Some(event))
                    }
                }
            }
            PushPhase::Publish(prepared) => {
                self.phase = PushPhase::Prepare;
                match repo.publish_push(&prepared, self.force) {
                    Err(Fail::Hard) => Err(Fail::Hard),
                    Err(_) => {
                        self.failures.push(prepared.path);
                        Ok(None)
                    }
                    Ok(()) => {
                        self.track(repo, &prepared.path)?;
                        Ok(Some(ExecutionEvent::AfterPush {
                            path: prepared.path,
                            commit: prepared.rebuilt_commit,
                        }))
                    }
                }
            }
        }
    }

    fn track(&mut self, repo: &mut Repo, path: &str) -> Res<()> {
        let Some(wanted) = &self.tracked_branch else {
            return Ok(());
        };
        // A no-op push may leave no branch to track.
        let reference = repo.splice_ref(path, wanted);
        if !git(&["rev-parse", "--verify", "--quiet", &reference])
            .q()
            .ok()
        {
            log_err(format!(
                "{path}: upstream has no '{wanted}' branch to track -- the push didn't create it"
            ));
            self.failures.push(path.to_string());
        } else {
            match repo.track_branch(path, &self.branch, wanted) {
                Err(Fail::Hard) => return Err(Fail::Hard),
                Err(_) => self.failures.push(path.to_string()),
                Ok(()) => {}
            }
        }
        Ok(())
    }

    fn finish(&self) -> Res<i32> {
        if !self.done() {
            return die("push still has pending work");
        }
        if self.failures.is_empty() {
            Ok(0)
        } else {
            log_err(format!("Failed: {}", self.failures.join(" ")));
            Ok(1)
        }
    }
}

impl Operation for PushProgress {
    const NAME: &'static str = "push";
    const CHECK_TRACKED_STATE: bool = false;

    fn done(&self) -> bool {
        PushProgress::done(self)
    }
    fn advance(&mut self, repo: &mut Repo) -> Res<Option<ExecutionEvent>> {
        PushProgress::advance(self, repo)
    }
    fn finish(&self) -> Res<i32> {
        PushProgress::finish(self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::test_repo::{git, with_repository};

    struct SpliceFixture {
        path: &'static str,
        upstream: &'static str,
        files: &'static [(&'static str, &'static str)],
    }

    impl SpliceFixture {
        fn offline_path(&self) -> std::path::PathBuf {
            std::path::Path::new(self.upstream).with_extension("offline")
        }

        fn disconnect(&self) {
            std::fs::rename(self.upstream, self.offline_path()).unwrap();
        }
    }

    fn setup_splices(splices: &[SpliceFixture]) {
        git(&["commit", "--allow-empty", "-qm", "initial"]);
        for splice in splices {
            git(&[
                "init",
                "-q",
                "--bare",
                "--initial-branch=main",
                splice.upstream,
            ]);
            std::fs::create_dir_all(splice.path).unwrap();
            for (file, content) in splice.files {
                let file = std::path::Path::new(splice.path).join(file);
                std::fs::create_dir_all(file.parent().unwrap()).unwrap();
                std::fs::write(file, content).unwrap();
            }
            std::fs::write(
                format!("{}/.splice", splice.path),
                format!(
                    "[splice]\n id = {}\n[upstream \"origin\"]\n url = {}\n",
                    splice.path, splice.upstream
                ),
            )
            .unwrap();
            git(&["add", "--", splice.path]);
        }
        git(&["commit", "-qm", "mount splices"]);
    }

    fn setup() {
        setup_splices(&[
            SpliceFixture {
                path: "vendor/a",
                upstream: "vendor/a.git",
                files: &[("file", "vendor/a")],
            },
            SpliceFixture {
                path: "vendor/b",
                upstream: "vendor/b.git",
                files: &[("file", "vendor/b")],
            },
        ]);
    }

    fn assert_push_diagram(
        checkpoint: &str,
        splices: &[SpliceFixture],
        commits: &[(&str, &str)],
        expected: &str,
    ) {
        let label = |commit: &str| {
            if commit.is_empty() {
                return "-".to_string();
            }
            commits
                .iter()
                .find(|(_, id)| *id == commit)
                .map(|(name, _)| (*name).to_string())
                .unwrap_or_else(|| commit.to_string())
        };
        let branch = git(&["symbolic-ref", "--short", "HEAD"]);
        let head = label(&git(&["rev-parse", "HEAD"]));
        let local = commits
            .iter()
            .map(|(name, id)| {
                if commit_here(id) {
                    (*name).to_string()
                } else {
                    format!("{name} (missing)")
                }
            })
            .collect::<Vec<_>>()
            .join(" ");
        let mut diagram = format!("{branch} -> {head}\nnamed local commits: {local}");
        for splice in splices {
            let online = std::path::Path::new(splice.upstream).exists();
            let repository = if online {
                std::path::PathBuf::from(splice.upstream)
            } else {
                splice.offline_path()
            };
            let commit = git(&[
                &format!("--git-dir={}", repository.display()),
                "for-each-ref",
                "--format=%(objectname)",
                "refs/heads/topic",
            ]);
            let state = if online { "online" } else { "offline" };
            diagram.push_str(&format!(
                "\n{}/topic -> {} ({state})",
                splice.upstream,
                label(&commit)
            ));
        }
        println!("\n{checkpoint}\n{diagram}\n");
        assert_eq!(
            diagram, expected,
            "{checkpoint}: observed repository diagram:\n{diagram}"
        );
    }

    fn progress<'a>(context: &'a mut ExecutionContext) -> (Repo<'a>, PushProgress) {
        let mut repo = Repo::new(
            context,
            parse_args(
                USAGE,
                "--force --branch --track",
                &[
                    "--force".into(),
                    "--branch".into(),
                    "topic".into(),
                    "--track".into(),
                    "--all".into(),
                ],
            )
            .unwrap(),
        );
        repo.open().unwrap();
        let progress = PushProgress::new(&mut repo).unwrap();
        (repo, progress)
    }

    #[test]
    fn exec_hooks_observe_prepared_and_published_commits_from_the_repository_root() {
        with_repository(|| {
            setup();
            let mut context = ExecutionContext::new();
            let observed = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
            let events = observed.clone();
            context.set_observer(move |event| events.lock().unwrap().push(event.clone()));
            let hook = r#"
set -eu
test "$GIT_SPLICE_PATH" = vendor/a
git cat-file -e "$GIT_SPLICE_COMMIT^{commit}"
case "$GIT_SPLICE_EVENT" in
    after-rebuild) test -z "$(git --git-dir=vendor/a.git for-each-ref)" ;;
    after-push) test "$(git --git-dir=vendor/a.git rev-parse topic)" = "$GIT_SPLICE_COMMIT" ;;
    *) exit 1 ;;
esac
printf '%s\n' "$GIT_SPLICE_EVENT" >> hook-events
"#;
            std::env::set_current_dir("vendor/a").unwrap();
            let mut execution = start(
                &mut context,
                &[
                    "--branch=topic".into(),
                    format!("--exec={hook}"),
                    "vendor/a".into(),
                ],
            )
            .unwrap();
            assert_eq!(execution.run(), Ok(0));
            assert_eq!(execution.run(), Ok(0));
            assert_eq!(
                std::fs::read_to_string("hook-events").unwrap(),
                "after-rebuild\nafter-push\n"
            );
            assert_eq!(observed.lock().unwrap().len(), 2);
        });
    }

    #[test]
    fn failing_exec_hook_stops_remaining_work_and_remains_failed() {
        for stop in ["after-rebuild", "after-push"] {
            with_repository(|| {
                setup();
                let mut context = ExecutionContext::new();
                let hook = format!(r#"if test "$GIT_SPLICE_EVENT" = {stop}; then exit 7; fi"#);
                let mut execution =
                    start(&mut context, &["--exec".into(), hook, "vendor/a".into()]).unwrap();
                assert_eq!(execution.run(), Err(Fail::Code(7)));
                assert_eq!(execution.run(), Err(Fail::Code(7)));
                let published = !git(&["--git-dir=vendor/a.git", "for-each-ref"]).is_empty();
                assert_eq!(published, stop == "after-push");
            });
        }
    }

    #[test]
    fn exec_hook_that_changes_head_is_rejected_before_publication() {
        with_repository(|| {
            setup();
            let mut context = ExecutionContext::new();
            assert_eq!(
                run(
                    &mut context,
                    &[
                        "--exec".into(),
                        "git commit --allow-empty -qm changed".into(),
                        "vendor/a".into(),
                    ],
                ),
                Err(Fail::Hard)
            );
            assert!(git(&["--git-dir=vendor/a.git", "for-each-ref"]).is_empty());
        });
    }

    #[test]
    fn named_push_checkpoints_pause_and_continue_without_repeating_publication() {
        with_repository(|| {
            let splices = [
                SpliceFixture {
                    path: "vendor/a",
                    upstream: "vendor/a.git",
                    files: &[("file", "a's committed content")],
                },
                SpliceFixture {
                    path: "vendor/b",
                    upstream: "vendor/b.git",
                    files: &[("file", "b's committed content")],
                },
            ];
            setup_splices(&splices);
            let main = git(&["rev-parse", "HEAD"]);
            assert_push_diagram(
                "Initial fixture",
                &splices,
                &[("M", &main)],
                r#"main -> M
named local commits: M
vendor/a.git/topic -> - (online)
vendor/b.git/topic -> - (online)"#,
            );
            let mut context = ExecutionContext::new();
            let observed = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
            let events = observed.clone();
            context.set_observer(move |event| events.lock().unwrap().push(event.clone()));
            let args = [
                "--all".into(),
                "--force".into(),
                "--branch".into(),
                "topic".into(),
                "--track".into(),
            ];
            let mut execution = start(&mut context, &args).unwrap();
            let paused = execution
                .run_until(|event| matches!(event, ExecutionEvent::AfterRebuild { .. }))
                .unwrap();
            let ExecutionOutcome::Paused(ExecutionEvent::AfterRebuild { path, commit }) = paused
            else {
                panic!("expected rebuild pause")
            };
            assert_eq!(path, "vendor/a");
            assert_push_diagram(
                "Paused: a rebuilt, not published",
                &splices,
                &[("M", &main), ("A", &commit)],
                r#"main -> M
named local commits: M A
vendor/a.git/topic -> - (online)
vendor/b.git/topic -> - (online)"#,
            );
            assert!(git(&["--git-dir=vendor/a.git", "for-each-ref"]).is_empty());
            assert!(git(&["--git-dir=vendor/b.git", "for-each-ref"]).is_empty());
            std::fs::write("vendor/a/file", "uncommitted content").unwrap();
            assert_eq!(
                execution
                    .run_until(|event| matches!(event, ExecutionEvent::AfterPush { .. }))
                    .unwrap(),
                ExecutionOutcome::Paused(ExecutionEvent::AfterPush {
                    path: "vendor/a".into(),
                    commit: commit.clone()
                }),
            );
            assert_eq!(
                git(&["--git-dir=vendor/a.git", "rev-parse", "refs/heads/topic"]),
                commit
            );
            assert_eq!(
                git(&["--git-dir=vendor/a.git", "show", "topic:file"]),
                "a's committed content"
            );
            assert_eq!(git(&["config", "--get", "branch.main.splice"]), "a:topic");
            assert_push_diagram(
                "Paused: a published",
                &splices,
                &[("M", &main), ("A", &commit)],
                r#"main -> M
named local commits: M A
vendor/a.git/topic -> A (online)
vendor/b.git/topic -> - (online)"#,
            );
            splices[0].disconnect();
            let paused = execution
                .run_until(|event| matches!(event, ExecutionEvent::AfterRebuild { .. }))
                .unwrap();
            let ExecutionOutcome::Paused(ExecutionEvent::AfterRebuild {
                path,
                commit: b_commit,
            }) = paused
            else {
                panic!("expected b's rebuild pause: {paused:#?}")
            };
            assert_eq!(path, "vendor/b");
            assert_push_diagram(
                "Paused: b rebuilt, a offline",
                &splices,
                &[("M", &main), ("A", &commit), ("B", &b_commit)],
                r#"main -> M
named local commits: M A B
vendor/a.git/topic -> A (offline)
vendor/b.git/topic -> - (online)"#,
            );
            assert!(git(&["--git-dir=vendor/b.git", "for-each-ref"]).is_empty());
            assert_eq!(execution.run().unwrap(), 0);
            assert!(!git(&["--git-dir=vendor/b.git", "for-each-ref"]).is_empty());
            assert_push_diagram(
                "Complete: b published",
                &splices,
                &[("M", &main), ("A", &commit), ("B", &b_commit)],
                r#"main -> M
named local commits: M A B
vendor/a.git/topic -> A (offline)
vendor/b.git/topic -> B (online)"#,
            );
            splices[1].disconnect();
            assert_eq!(
                execution.run_until(|_| true).unwrap(),
                ExecutionOutcome::Complete(0)
            );
            assert_eq!(execution.run().unwrap(), 0);
            assert_push_diagram(
                "Still complete: both upstreams offline",
                &splices,
                &[("M", &main), ("A", &commit), ("B", &b_commit)],
                r#"main -> M
named local commits: M A B
vendor/a.git/topic -> A (offline)
vendor/b.git/topic -> B (offline)"#,
            );
            let events = observed.lock().unwrap();
            assert_eq!(
                *events,
                vec![
                    ExecutionEvent::AfterRebuild {
                        path: "vendor/a".into(),
                        commit: commit.clone()
                    },
                    ExecutionEvent::AfterPush {
                        path: "vendor/a".into(),
                        commit
                    },
                    ExecutionEvent::AfterRebuild {
                        path: "vendor/b".into(),
                        commit: b_commit.clone()
                    },
                    ExecutionEvent::AfterPush {
                        path: "vendor/b".into(),
                        commit: b_commit
                    },
                ],
                "observed events:\n{events:#?}"
            );
        });
    }

    #[test]
    fn switching_repositories_before_first_advance_rejects_publication_and_remains_failed() {
        for use_predicate in [false, true] {
            with_repository(|| {
                setup();
                let root = std::env::current_dir().unwrap();
                git(&[
                    "config",
                    "--file",
                    "vendor/a/.splice",
                    "upstream.origin.url",
                    root.join("vendor/a.git").to_str().unwrap(),
                ]);
                git(&["commit", "-qam", "use absolute upstream"]);
                git(&["clone", "-q", ".", "other"]);
                std::fs::write("other/vendor/a/file", "other repository content").unwrap();
                git(&["-C", "other", "commit", "-qam", "other content"]);
                let mut context = ExecutionContext::new();
                let args = [
                    "--force".into(),
                    "--branch".into(),
                    "topic".into(),
                    "vendor/a".into(),
                ];
                let mut execution = start(&mut context, &args).unwrap();
                std::env::set_current_dir(root.join("other")).unwrap();
                let failed = if use_predicate {
                    execution.run_until(|_| false).is_err()
                } else {
                    execution.run().is_err()
                };
                std::env::set_current_dir(&root).unwrap();
                assert!(failed, "use_predicate={use_predicate}");
                assert!(execution.run().is_err());
                assert!(git(&["--git-dir=vendor/a.git", "for-each-ref"]).is_empty());
            });
        }
    }

    #[test]
    fn changed_local_state_rejects_continuation_before_publication_and_remains_failed() {
        for change in [
            "head",
            "branch",
            "fetched refs",
            "configuration",
            "repository",
        ] {
            with_repository(|| {
                setup();
                let root = std::env::current_dir().unwrap();
                let mut context = ExecutionContext::new();
                let args = [
                    "--force".into(),
                    "--branch".into(),
                    "topic".into(),
                    "vendor/a".into(),
                ];
                let mut execution = start(&mut context, &args).unwrap();
                assert!(matches!(
                    execution.run_until(|_| true).unwrap(),
                    ExecutionOutcome::Paused(ExecutionEvent::AfterRebuild { .. })
                ));
                match change {
                    "head" => {
                        git(&["commit", "--allow-empty", "-qm", "changed HEAD"]);
                    }
                    "branch" => {
                        git(&["checkout", "-qb", "another"]);
                    }
                    "fetched refs" => {
                        git(&["update-ref", "refs/splices/changed/heads/main", "HEAD"]);
                    }
                    "configuration" => {
                        git(&["config", "test.changed", "true"]);
                    }
                    "repository" => {
                        git(&["init", "-q", "--initial-branch=main", "other"]);
                        git(&["-C", "other", "commit", "--allow-empty", "-qm", "other"]);
                        std::env::set_current_dir(root.join("other")).unwrap();
                    }
                    _ => unreachable!(),
                }
                assert!(execution.run().is_err(), "{change}");
                std::env::set_current_dir(&root).unwrap();
                assert!(execution.run_until(|_| false).is_err(), "{change}");
                assert!(git(&["--git-dir=vendor/a.git", "for-each-ref"]).is_empty());
            });
        }
    }

    #[test]
    fn checkpoint_predicate_cannot_change_head_before_pausing_or_continuing() {
        for pause in [false, true] {
            with_repository(|| {
                setup();
                let mut context = ExecutionContext::new();
                let args = [
                    "--force".into(),
                    "--branch".into(),
                    "topic".into(),
                    "vendor/a".into(),
                ];
                let mut execution = start(&mut context, &args).unwrap();
                assert!(execution
                    .run_until(|_| {
                        git(&["commit", "--allow-empty", "-qm", "changed in predicate"]);
                        pause
                    })
                    .is_err());
                assert!(execution.run().is_err());
                assert!(git(&["--git-dir=vendor/a.git", "for-each-ref"]).is_empty());
            });
        }
    }

    #[test]
    fn pause_after_an_independent_push_preserves_an_earlier_publication_failure() {
        with_repository(|| {
            setup();
            let mut context = ExecutionContext::new();
            let args = [
                "--all".into(),
                "--force".into(),
                "--branch".into(),
                "topic".into(),
            ];
            let mut execution = start(&mut context, &args).unwrap();
            std::fs::rename("vendor/a.git", "vendor/a.offline").unwrap();
            let paused = execution
                .run_until(|event| matches!(event, ExecutionEvent::AfterPush { .. }))
                .unwrap();
            let published = git(&["--git-dir=vendor/b.git", "rev-parse", "refs/heads/topic"]);
            assert_eq!(
                paused,
                ExecutionOutcome::Paused(ExecutionEvent::AfterPush {
                    path: "vendor/b".into(),
                    commit: published,
                })
            );
            std::fs::rename("vendor/b.git", "vendor/b.offline").unwrap();
            assert_eq!(execution.run().unwrap(), 1);
            assert_eq!(
                execution.run_until(|_| true).unwrap(),
                ExecutionOutcome::Complete(1)
            );
        });
    }

    #[test]
    fn observer_sees_rebuilds_before_publication_and_published_commits_afterward() {
        with_repository(|| {
            setup();
            let mut context = ExecutionContext::new();
            let events = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
            let recorded = events.clone();
            context.set_observer(move |event| {
                match event {
                    ExecutionEvent::AfterRebuild { path, commit } => {
                        assert!(commit_here(commit));
                        assert!(git(&[&format!("--git-dir={path}.git"), "for-each-ref"]).is_empty());
                    }
                    ExecutionEvent::AfterPush { path, commit } => {
                        assert_eq!(git(&[&format!("--git-dir={path}.git"), "rev-parse", "refs/heads/topic"]), *commit);
                    }
                    _ => panic!("unexpected checkpoint: {event:?}"),
                }
                recorded.lock().unwrap().push(event.clone());
            });
            let args = [
                "--all".into(),
                "--force".into(),
                "--branch".into(),
                "topic".into(),
                "--track".into(),
            ];
            assert_eq!(run(&mut context, &args).unwrap(), 0);
            let observed = events.lock().unwrap();
            let a_commit = git(&["--git-dir=vendor/a.git", "rev-parse", "refs/heads/topic"]);
            let b_commit = git(&["--git-dir=vendor/b.git", "rev-parse", "refs/heads/topic"]);
            assert_eq!(
                *observed,
                vec![
                    ExecutionEvent::AfterRebuild {
                        path: "vendor/a".into(),
                        commit: a_commit.clone()
                    },
                    ExecutionEvent::AfterPush {
                        path: "vendor/a".into(),
                        commit: a_commit
                    },
                    ExecutionEvent::AfterRebuild {
                        path: "vendor/b".into(),
                        commit: b_commit.clone()
                    },
                    ExecutionEvent::AfterPush {
                        path: "vendor/b".into(),
                        commit: b_commit
                    },
                ],
                "observed events:\n{observed:#?}"
            );
            drop(observed);
            events.lock().unwrap().clear();
            assert_eq!(run(&mut context, &args).unwrap(), 0);
            assert!(events.lock().unwrap().is_empty());
            context.clear_observer();
            std::fs::write("vendor/a/file", "changed").unwrap();
            git(&["add", "vendor/a/file"]);
            git(&["commit", "-qm", "new local content"]);
            assert_eq!(run(&mut context, &args).unwrap(), 0);
            assert!(events.lock().unwrap().is_empty());
        });
    }

    #[test]
    fn preparation_leaves_remote_unchanged_and_publication_advances_once_before_next_splice() {
        with_repository(|| {
            setup();
            let mut context = ExecutionContext::new();
            let (mut repo, mut progress) = progress(&mut context);
            assert_eq!(progress.paths.front().unwrap(), "vendor/a");
            let event = progress.advance(&mut repo).unwrap();
            let PushPhase::Publish(prepared) = &progress.phase else {
                panic!("expected prepared push")
            };
            let rebuilt = prepared.rebuilt_commit.clone();
            let reference = prepared.fetched_ref.clone();
            assert_eq!(
                event,
                Some(ExecutionEvent::AfterRebuild {
                    path: "vendor/a".into(),
                    commit: rebuilt.clone(),
                })
            );
            assert!(git(&["--git-dir=vendor/a.git", "for-each-ref"]).is_empty());
            assert!(git(&["--git-dir=vendor/b.git", "for-each-ref"]).is_empty());
            repo.c = Classified::default();
            assert_eq!(
                progress.advance(&mut repo).unwrap(),
                Some(ExecutionEvent::AfterPush {
                    path: "vendor/a".into(),
                    commit: rebuilt.clone(),
                })
            );
            assert_eq!(
                git(&["--git-dir=vendor/a.git", "rev-parse", "refs/heads/topic"]),
                rebuilt
            );
            assert_eq!(git(&["rev-parse", &reference]), rebuilt);
            assert!(git(&["--git-dir=vendor/b.git", "for-each-ref"]).is_empty());
            assert_eq!(git(&["config", "--get", "branch.main.splice"]), "a:topic");
            std::fs::rename("vendor/a.git", "vendor/a.offline").unwrap();
            while !progress.done() {
                progress.advance(&mut repo).unwrap();
            }
            assert_eq!(progress.finish().unwrap(), 0);
            assert!(!git(&["--git-dir=vendor/b.git", "for-each-ref"]).is_empty());
            std::fs::rename("vendor/b.git", "vendor/b.offline").unwrap();
            assert_eq!(progress.advance(&mut repo).unwrap(), None);
            assert!(progress.done());
            assert_eq!(progress.finish().unwrap(), 0);
        });
    }

    #[test]
    fn publication_failure_blocks_ancestors_but_allows_an_independent_splice() {
        with_repository(|| {
            setup();
            let mut context = ExecutionContext::new();
            git(&[
                "init",
                "-q",
                "--bare",
                "--initial-branch=main",
                "upstream.git",
            ]);
            std::fs::write(
                "vendor/.splice",
                "[splice]\n id = parent\n[upstream \"origin\"]\n url = upstream.git\n",
            )
            .unwrap();
            git(&["add", "vendor/.splice"]);
            git(&["commit", "-qm", "mount parent"]);
            let (mut repo, mut progress) = progress(&mut context);
            progress.advance(&mut repo).unwrap();
            assert!(matches!(progress.phase, PushPhase::Publish(_)));
            std::fs::rename("vendor/a.git", "vendor/a.offline").unwrap();
            progress.advance(&mut repo).unwrap();
            assert_eq!(progress.failures, ["vendor/a"]);
            while !progress.done() {
                progress.advance(&mut repo).unwrap();
            }
            assert_eq!(progress.finish().unwrap(), 1);
            assert_eq!(progress.failures, ["vendor/a", "vendor"]);
            assert!(!git(&["--git-dir=vendor/b.git", "for-each-ref"]).is_empty());
        });
    }
}
