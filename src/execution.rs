//! Typed observations and in-memory synchronization drivers.

use crate::repo::{commit_of, Repo};
use crate::util::*;
use std::process::{Command, Stdio};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FetchedUpstream {
    pub path: String,
    pub upstream: String,
    pub url: String,
    /// The download report failed; this does not describe synced-history validity.
    pub failed: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ExecutionEvent {
    /// Downloads are done and reported; new upstreams that all failed are forgotten.
    AfterFetch { fetched: Vec<FetchedUpstream> },
    /// HEAD changed without an unresolved splice conflict; discovery may follow.
    AfterMerge {
        path: String,
        head_before: String,
        head_after: String,
    },
    /// A commit is prepared for publication; this step has not pushed it yet.
    AfterRebuild { path: String, commit: String },
    /// Publication and its local fetched-ref update succeeded.
    AfterPush { path: String, commit: String },
    /// The fold stage is about to run, including when it has nothing to fold.
    BeforeFold { roots: Vec<String>, head: String },
    /// Folding returned successfully; rebase replay and cleanup may follow.
    AfterFold {
        roots: Vec<String>,
        head_before: String,
        head_after: String,
    },
}

/// Result of driving an operation to completion or a requested event boundary.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ExecutionOutcome {
    Paused(ExecutionEvent),
    Complete(i32),
}

impl ExecutionEvent {
    /// The event's name, splice and commit, as --exec hooks get them.
    fn hook_values(&self) -> (&str, &str, &str) {
        match self {
            Self::AfterFetch { .. } => ("after-fetch", "", ""),
            Self::AfterMerge { path, .. } => ("after-merge", path, ""),
            Self::AfterRebuild { path, commit } => ("after-rebuild", path, commit),
            Self::AfterPush { path, commit } => ("after-push", path, commit),
            Self::BeforeFold { .. } => ("before-fold", "", ""),
            Self::AfterFold { .. } => ("after-fold", "", ""),
        }
    }

    fn exec(&self, command: &str, operation: &str) -> Res<()> {
        let (event, path, commit) = self.hook_values();
        let status = match Command::new("sh")
            .args(["-c", command])
            .env("GIT_SPLICE_EVENT", event)
            .env("GIT_SPLICE_PATH", path)
            .env("GIT_SPLICE_COMMIT", commit)
            .stdin(Stdio::null())
            .status()
        {
            Ok(status) => status,
            Err(error) => return die(format!("--exec: could not run command: {error}")),
        };
        if !status.success() {
            let of = if path.is_empty() {
                String::new()
            } else {
                format!(" of {path}")
            };
            log_err(format!(
                "--exec stopped {operation} at {event}{of}, what it did so far stays -- re-run {operation} to go on"
            ));
            return Err(Fail::Code(status_code(status)));
        }
        Ok(())
    }
}

pub(crate) trait Operation {
    const NAME: &'static str;
    const CHECK_TRACKED_STATE: bool;
    fn done(&self) -> bool;
    fn advance(&mut self, repo: &mut Repo) -> Res<Option<ExecutionEvent>>;
    fn finish(&self) -> Res<i32>;
    /// Says what else an --exec hook that stopped the operation left behind.
    fn stopped(&self) {}
}

pub(crate) struct Execution<'context, O> {
    repo: Repo<'context>,
    progress: O,
    paused: Option<PausedRepository>,
    completed: Option<i32>,
    failed: Option<Fail>,
}

type PausePredicate<'a> = &'a mut dyn FnMut(&ExecutionEvent) -> bool;

impl<'context, O: Operation> Execution<'context, O> {
    pub(crate) fn new(repo: Repo<'context>, progress: O) -> Res<Self> {
        let initial = PausedRepository::capture(O::CHECK_TRACKED_STATE)?;
        Ok(Self {
            repo,
            progress,
            paused: Some(initial),
            completed: None,
            failed: None,
        })
    }

    pub(crate) fn run(&mut self) -> Res<i32> {
        match self.drive(None)? {
            ExecutionOutcome::Complete(status) => Ok(status),
            ExecutionOutcome::Paused(_) => unreachable!("no pause predicate installed"),
        }
    }

    pub(crate) fn run_until(
        &mut self,
        mut stop: impl FnMut(&ExecutionEvent) -> bool,
    ) -> Res<ExecutionOutcome> {
        self.drive(Some(&mut stop))
    }
    fn drive(&mut self, mut stop: Option<PausePredicate<'_>>) -> Res<ExecutionOutcome> {
        if let Some(failure) = self.failed {
            return Err(failure);
        }
        if let Some(status) = self.completed {
            return Ok(ExecutionOutcome::Complete(status));
        }
        if let Some(paused) = &self.paused {
            let validated = paused.validate(O::NAME);
            self.checked(validated)?;
        }
        self.paused = None;
        while !self.progress.done() {
            let advanced = self.progress.advance(&mut self.repo);
            if let Some(event) = self.checked(advanced)? {
                self.repo.context.emit(event.clone());
                let command = self.repo.args.exec.clone();
                if command.is_empty() && stop.is_none() {
                    continue;
                }
                let checkpoint = self.checked(PausedRepository::capture(O::CHECK_TRACKED_STATE))?;
                if !command.is_empty() {
                    if let Err(failure) = event.exec(&command, O::NAME) {
                        self.progress.stopped();
                        return self.checked(Err(failure));
                    }
                }
                let pause = stop.as_mut().is_some_and(|predicate| predicate(&event));
                self.checked(checkpoint.validate(O::NAME))?;
                if pause {
                    self.paused = Some(checkpoint);
                    return Ok(ExecutionOutcome::Paused(event));
                }
            }
        }
        let finished = self.progress.finish();
        let status = self.checked(finished)?;
        self.completed = Some(status);
        Ok(ExecutionOutcome::Complete(status))
    }

    fn checked<T>(&mut self, result: Res<T>) -> Res<T> {
        if let Err(failure) = &result {
            self.failed = Some(*failure);
        }
        result
    }
}

#[derive(PartialEq, Eq)]
struct PausedRepository {
    root: std::path::PathBuf,
    git_dir: String,
    head: String,
    branch: Option<String>,
    fetched_refs: String,
    config: Vec<u8>,
    tracked: Option<TrackedState>,
}

impl PausedRepository {
    fn capture(check_tracked_state: bool) -> Res<Self> {
        Ok(Self {
            root: std::env::current_dir().map_err(|_| Fail::Hard)?,
            git_dir: git(&["rev-parse", "--absolute-git-dir"])
                .out()
                .ok_or(Fail::Hard)?,
            head: commit_of("HEAD").ok_or(Fail::Hard)?,
            branch: git(&["symbolic-ref", "--quiet", "HEAD"]).q().out(),
            fetched_refs: git(&[
                "for-each-ref",
                "--format=%(refname) %(objectname)",
                "refs/splices/",
            ])
            .out()
            .ok_or(Fail::Hard)?,
            config: git(&["config", "--null", "--list"])
                .bytes()
                .ok_or(Fail::Hard)?,
            tracked: if check_tracked_state {
                Some(TrackedState::capture()?)
            } else {
                None
            },
        })
    }

    fn validate(&self, operation: &str) -> Res<()> {
        if *self != Self::capture(self.tracked.is_some())? {
            return die(format!(
                "repository state changed at a {operation} checkpoint -- start a new {operation}"
            ));
        }
        Ok(())
    }
}

#[derive(PartialEq, Eq)]
struct TrackedState {
    index: String,
    worktree: String,
    fold_start: Option<Vec<u8>>,
    rebase_branch: Option<Vec<u8>>,
    rebase_tip: Option<String>,
}

impl TrackedState {
    fn capture() -> Res<Self> {
        let diff = git(&[
            "diff",
            "--binary",
            "--no-ext-diff",
            "--no-textconv",
            "HEAD",
            "--",
        ])
        .bytes()
        .ok_or(Fail::Hard)?;
        Ok(Self {
            index: git(&["write-tree"]).out().ok_or(Fail::Hard)?,
            worktree: git(&["hash-object", "--stdin"])
                .input(diff)
                .out()
                .ok_or(Fail::Hard)?,
            fold_start: Self::marker("SPLICE_PULL_START")?,
            rebase_branch: Self::marker("SPLICE_PULL_BRANCH")?,
            rebase_tip: commit_of("SPLICE_PULL_BRANCH"),
        })
    }

    fn marker(name: &str) -> Res<Option<Vec<u8>>> {
        let path = git(&["rev-parse", "--git-path", name])
            .out()
            .ok_or(Fail::Hard)?;
        match std::fs::read(path) {
            Ok(bytes) => Ok(Some(bytes)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(_) => Err(Fail::Hard),
        }
    }
}
