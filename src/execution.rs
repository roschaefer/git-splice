//! Typed observations and in-memory synchronization drivers.

use serde::{Deserialize, Serialize};

use crate::args::Args;
use crate::repo::{commit_of, Repo, SavedRepo};
use crate::tree::Tasks;
use crate::util::*;
use serde::de::DeserializeOwned;
use std::process::{Command, Stdio};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FetchedUpstream {
    pub path: String,
    pub upstream: String,
    pub url: String,
    /// The download report failed; this does not describe synced-history validity.
    pub failed: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "checkpoint", rename_all = "kebab-case")]
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
    pub(crate) fn hook_values(&self) -> (&str, &str, &str) {
        match self {
            Self::AfterFetch { .. } => ("after-fetch", "", ""),
            Self::AfterMerge { path, .. } => ("after-merge", path, ""),
            Self::AfterRebuild { path, commit } => ("after-rebuild", path, commit),
            Self::AfterPush { path, commit } => ("after-push", path, commit),
            Self::BeforeFold { .. } => ("before-fold", "", ""),
            Self::AfterFold { .. } => ("after-fold", "", ""),
        }
    }

    fn exec(&self, command: &str, operation: &str, input: Vec<u8>) -> Res<()> {
        let (event, path, commit) = self.hook_values();
        let mut child = match Command::new("sh")
            .args(["-c", command])
            .env("GIT_SPLICE_EVENT", event)
            .env("GIT_SPLICE_PATH", path)
            .env("GIT_SPLICE_COMMIT", commit)
            .stdin(Stdio::piped())
            .spawn()
        {
            Ok(child) => child,
            Err(error) => return die(format!("--exec: could not run command: {error}")),
        };
        let mut stdin = child.stdin.take().ok_or(Fail::Hard)?;
        let writer = std::thread::spawn(move || {
            use std::io::Write;
            stdin.write_all(&input)
        });
        let status = child.wait().map_err(|_| Fail::Hard)?;
        let written = writer.join().map_err(|_| Fail::Hard)?;
        if !status.success() {
            let of = if path.is_empty() {
                String::new()
            } else {
                format!(" of {path}")
            };
            log_err(format!(
                "--exec stopped {operation} at {event}{of}, what it did so far stays -- resume a saved stdin payload with --continue-from, or re-run {operation}"
            ));
            return Err(Fail::Code(status_code(status)));
        }
        if let Err(error) = written {
            if error.kind() != std::io::ErrorKind::BrokenPipe {
                return die(format!("--exec: could not send continuation: {error}"));
            }
        }
        Ok(())
    }
}

pub(crate) trait Operation: Serialize + DeserializeOwned {
    const NAME: &'static str;
    const CHECK_TRACKED_STATE: bool;
    fn done(&self) -> bool;
    fn advance(&mut self, repo: &mut Repo) -> Res<Option<ExecutionEvent>>;
    fn finish(&self) -> Res<i32>;
    /// Says what else an --exec hook that stopped the operation left behind.
    fn stopped(&self) {}
    /// Commits pending publication still needs after a pause.
    fn retained_commits(&self) -> Vec<String> {
        Vec::new()
    }

    /// The work done and still to do, per splice.
    fn tasks(&self) -> Tasks {
        Tasks::default()
    }
}

pub(crate) struct Execution<'context, O> {
    repo: Repo<'context>,
    progress: O,
    paused: Option<PausedRepository>,
    completed: Option<i32>,
    failed: Option<Fail>,
    retained: Option<(String, Vec<String>)>,
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
            retained: None,
        })
    }

    pub(crate) fn run(&mut self) -> Res<i32> {
        let pause_after = self.repo.args.pause_after.clone();
        if !pause_after.is_empty() {
            let outcome = self.run_until(|event| event.hook_values().0 == pause_after)?;
            if let ExecutionOutcome::Paused(ref event) = outcome {
                self.save(event)?;
                return Ok(75);
            }
            if let ExecutionOutcome::Complete(status) = outcome {
                return Ok(status);
            }
        }
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
        if !self.repo.args.continue_from.is_empty() {
            std::fs::remove_file(&self.repo.args.continue_from).map_err(|error| {
                log_err(format!("could not consume continuation: {error}"));
                Fail::Hard
            })?;
            self.repo.args.continue_from.clear();
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
                    let payload = self.payload(&checkpoint, &event);
                    let (input, refs) = self.checked(payload)?;
                    let executed = event.exec(&command, O::NAME, input);
                    if !matches!(executed, Err(Fail::Code(_)))
                        || checkpoint.validate(O::NAME).is_err()
                    {
                        release_refs(&refs);
                    }
                    if let Err(failure) = executed {
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

    fn payload(
        &self,
        checkpoint: &PausedRepository,
        event: &ExecutionEvent,
    ) -> Res<(Vec<u8>, Vec<String>)> {
        let mut commits = self.progress.retained_commits();
        commits.extend(self.repo.context.supplied_rebuilds.values().cloned());
        commits.extend(
            self.repo
                .child_rebuilds
                .values()
                .filter_map(|(_, _, commit)| commit.clone()),
        );
        commits.sort();
        commits.dedup();
        let seed = format!(
            "{} {:?}",
            self.repo.args.save_to,
            std::time::SystemTime::now()
        );
        let key = git(&["hash-object", "--stdin"])
            .input(seed.into_bytes())
            .out()
            .ok_or(Fail::Hard)?;
        let refs: Vec<String> = commits
            .iter()
            .map(|commit| format!("refs/splice-continuations/{key}/{commit}"))
            .collect();
        for (reference, commit) in refs.iter().zip(&commits) {
            if !git(&["update-ref", reference, commit]).ok() {
                for reference in &refs {
                    git(&["update-ref", "-d", reference]).q().ok();
                }
                return die("could not retain continuation commits");
            }
        }
        let saved = SavedExecution {
            format: 1,
            event: Some(event.clone()),
            retained_refs: refs.clone(),
            version: env!("CARGO_PKG_VERSION").to_string(),
            operation: O::NAME.to_string(),
            repository: SavedRepo::capture(&self.repo),
            progress: &self.progress,
            checkpoint,
        };
        let mut bytes = serde_json::to_vec_pretty(&saved).map_err(|error| {
            log_err(format!("could not encode continuation: {error}"));
            Fail::Hard
        })?;
        bytes.push(b'\n');
        Ok((bytes, refs))
    }

    fn save(&self, event: &ExecutionEvent) -> Res<()> {
        let checkpoint = self.paused.as_ref().ok_or(Fail::Hard)?;
        let (bytes, refs) = self.payload(checkpoint, event)?;
        let path = &self.repo.args.save_to;
        let temporary = format!("{path}.tmp-{}", std::process::id());
        let mut created = false;
        let result = (|| -> std::io::Result<()> {
            use std::io::Write;
            let mut options = std::fs::OpenOptions::new();
            options.write(true).create_new(true);
            #[cfg(unix)]
            {
                use std::os::unix::fs::OpenOptionsExt;
                options.mode(0o600);
            }
            let mut file = options.open(&temporary)?;
            created = true;
            file.write_all(&bytes)?;
            file.sync_all()?;
            std::fs::hard_link(&temporary, path)?;
            std::fs::remove_file(&temporary)
        })();
        if let Err(error) = result {
            if created {
                let _ = std::fs::remove_file(&temporary);
            }
            for reference in &refs {
                git(&["update-ref", "-d", reference]).q().ok();
            }
            return die(format!("could not save continuation to {path}: {error}"));
        }
        log_ok(format!(
            "{} paused; continue with 'git splice {} --continue-from {}'",
            O::NAME,
            O::NAME,
            shell_quote(path)
        ));
        Ok(())
    }

    pub(crate) fn restore(
        context: &'context mut crate::context::ExecutionContext,
        args: Args,
    ) -> Res<Self> {
        let bytes = std::fs::read(&args.continue_from).map_err(|error| {
            log_err(format!("could not read continuation: {error}"));
            Fail::Hard
        })?;
        let saved: SavedExecution<O, PausedRepository> =
            serde_json::from_slice(&bytes).map_err(|error| {
                log_err(format!("invalid continuation: {error}"));
                Fail::Hard
            })?;
        if saved.format != 1
            || saved.version != env!("CARGO_PKG_VERSION")
            || saved.operation != O::NAME
        {
            return die("continuation belongs to another command or git-splice version -- start a new operation");
        }
        if saved.retained_refs.iter().any(|reference| {
            !reference.starts_with("refs/splice-continuations/")
                || !git(&["check-ref-format", reference]).q().ok()
        }) {
            return die("invalid continuation references");
        }
        saved.checkpoint.validate(O::NAME)?;
        let retained = Some((saved.checkpoint.git_dir.clone(), saved.retained_refs));
        let mut repo = saved.repository.restore(context)?;
        repo.args.exec = args.exec;
        repo.args.pause_after = args.pause_after;
        repo.args.save_to = args.save_to;
        repo.args.continue_from = args.continue_from;
        Ok(Self {
            repo,
            progress: saved.progress,
            paused: Some(saved.checkpoint),
            completed: None,
            failed: None,
            retained,
        })
    }

    /// The operation's work per splice, done and still to do.
    pub(crate) fn tasks(&self) -> Tasks {
        self.progress.tasks()
    }

    fn checked<T>(&mut self, result: Res<T>) -> Res<T> {
        if let Err(failure) = &result {
            self.failed = Some(*failure);
        }
        result
    }
}

#[derive(PartialEq, Eq, Serialize, Deserialize)]
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

#[derive(PartialEq, Eq, Serialize, Deserialize)]
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

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct SavedExecution<O, C> {
    format: u32,
    #[serde(default)]
    event: Option<ExecutionEvent>,
    retained_refs: Vec<String>,
    version: String,
    operation: String,
    repository: SavedRepo,
    progress: O,
    checkpoint: C,
}

pub(crate) const CONTINUATION_OPTIONS: &str = "--pause-after --save-to --continue-from";

pub(crate) fn validate_continuation_options(args: &mut Args, events: &[&str]) -> Res<()> {
    if (!args.pause_after.is_empty() || !args.save_to.is_empty() || !args.continue_from.is_empty())
        && git(&["rev-parse", "--show-prefix"])
            .q()
            .out()
            .is_some_and(|prefix| !prefix.is_empty())
    {
        return die("run saved continuation commands from the repository root");
    }
    if !args.pause_after.is_empty() && !events.contains(&args.pause_after.as_str()) {
        return die(format!("--pause-after needs one of: {}", events.join(", ")));
    }
    if !args.continue_from.is_empty() {
        let mut other = args.clone();
        other.exec.clear();
        other.pause_after.clear();
        other.save_to.clear();
        other.continue_from.clear();
        if other != Args::default() {
            return die("--continue-from retains the original options and paths -- give only continuation options and --exec");
        }
        if !args.pause_after.is_empty() && args.save_to.is_empty() {
            args.save_to = args.continue_from.clone();
        }
    }
    if args.pause_after.is_empty() != args.save_to.is_empty() {
        return die("--pause-after and --save-to must be given together");
    }
    if !args.save_to.is_empty() {
        let path = std::path::Path::new(&args.save_to);
        if path.exists() && args.save_to != args.continue_from {
            return die("--save-to already exists -- use a new file");
        }
        let parent = path
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or(std::path::Path::new("."));
        if !parent.is_dir() {
            return die("--save-to needs an existing parent directory");
        }
        if path.is_dir() {
            return die("--save-to must name a file");
        }
    }
    Ok(())
}

impl<O> Drop for Execution<'_, O> {
    fn drop(&mut self) {
        if !self.repo.args.continue_from.is_empty() {
            return;
        }
        if let Some((git_dir, refs)) = &self.retained {
            for reference in refs {
                git(&["--git-dir", git_dir, "update-ref", "-d", reference])
                    .q()
                    .ok();
            }
        }
    }
}

fn release_refs(refs: &[String]) {
    for reference in refs {
        git(&["update-ref", "-d", reference]).q().ok();
    }
}
