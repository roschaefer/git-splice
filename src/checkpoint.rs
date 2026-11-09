//! Script checkpoints and caller-owned continuation for fetch, pull and push.

use crate::args::Args;
use crate::context::ExecutionContext;
use crate::merge::{apply_merge_options, MergeProgress};
use crate::message::{Message, KNOWN};
use crate::repo::*;
use crate::util::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::process::{Command, Stdio};

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Fetched {
    pub path: String,
    pub upstream: String,
    pub url: String,
    pub reference: String,
    pub old: Option<String>,
    pub new: Option<String>,
    pub synced: String,
    pub failed: bool,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(tag = "checkpoint", rename_all = "kebab-case", deny_unknown_fields)]
pub(crate) enum Event {
    AfterFetch {
        fetched: Vec<Fetched>,
    },
    AfterMerge {
        path: String,
        upstream: String,
        url: String,
        old: String,
        new: String,
        target: Option<String>,
        rebuilt_commit: String,
        head_before: String,
        head_after: String,
    },
    AfterRebuild(crate::push::PreparedPush),
    AfterPush(crate::push::PreparedPush),
    BeforeFold,
    AfterFold,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Discovery {
    all_paths: Vec<String>,
    selected: Vec<String>,
    upstream_lists: HashMap<String, Vec<String>>,
    upstream_urls: Vec<((String, String), String)>,
    default_upstreams: HashMap<String, String>,
    upstream_names: HashMap<String, String>,
    urls: HashMap<String, String>,
    keys: HashMap<String, String>,
}

impl Discovery {
    fn capture(repo: &Repo) -> Self {
        Self {
            all_paths: repo.all_paths.clone(),
            selected: repo.selected.clone(),
            upstream_lists: repo.upstream_lists.clone(),
            upstream_urls: repo
                .upstream_urls
                .iter()
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect(),
            default_upstreams: repo.default_upstreams.clone(),
            upstream_names: repo.upstream_names.clone(),
            urls: repo.urls.clone(),
            keys: repo.keys.clone(),
        }
    }

    fn restore(self, repo: &mut Repo) {
        repo.all_paths = self.all_paths;
        repo.selected = self.selected;
        repo.upstream_lists = self.upstream_lists;
        repo.upstream_urls = self.upstream_urls.into_iter().collect();
        repo.default_upstreams = self.default_upstreams;
        repo.upstream_names = self.upstream_names;
        repo.urls = self.urls;
        repo.keys = self.keys;
    }
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
enum Phase {
    Merging,
    Pushing,
    Tracking,
    Fold,
    Done,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Continuation {
    #[serde(default)]
    pending_hooks: Vec<crate::config::ScheduledHook>,
    #[serde(default)]
    pending_event: Option<Event>,
    #[serde(default)]
    cli_hook: bool,
    args: Args,
    branch: String,
    fold_start: Option<String>,
    #[serde(default)]
    fold_roots: Vec<String>,
    fetch_failures: Vec<String>,
    merges: MergeProgress,
    phase: Phase,
    discovery: Discovery,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pushes: Option<crate::push::PushProgress>,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Repository {
    root: String,
    git_dir: String,
    head: String,
    branch: String,
    fetched_refs: String,
    config: String,
    fold_start: Option<String>,
}

impl Repository {
    fn capture() -> Res<Self> {
        let config = git(&["config", "--null", "--list"])
            .bytes()
            .ok_or(Fail::Hard)?;
        Ok(Self {
            root: std::env::current_dir()
                .map_err(|_| Fail::Hard)?
                .to_string_lossy()
                .into_owned(),
            git_dir: git(&["rev-parse", "--absolute-git-dir"])
                .out()
                .ok_or(Fail::Hard)?,
            head: git(&["rev-parse", "HEAD"]).out().ok_or(Fail::Hard)?,
            branch: current_branch()?,
            fetched_refs: git(&[
                "for-each-ref",
                "--format=%(refname) %(objectname)",
                "refs/splices/",
            ])
            .out()
            .ok_or(Fail::Hard)?,
            config: git(&["hash-object", "--stdin"])
                .input(config)
                .out()
                .ok_or(Fail::Hard)?,
            fold_start: commit_of("SPLICE_PULL_START"),
        })
    }

    fn validate(&self, operation: &str) -> Res<()> {
        let now = Self::capture()?;
        if self.root != now.root || self.git_dir != now.git_dir || self.branch != now.branch {
            return die("continuation belongs to another repository, worktree or branch");
        }
        if self.fetched_refs != now.fetched_refs || self.fold_start != now.fold_start {
            return die("fetched refs or SPLICE_PULL_START changed since the checkpoint -- start a new operation");
        }
        if self.config != now.config {
            return die("Git configuration changed since the checkpoint -- start a new operation");
        }
        if self.head != now.head {
            if operation == "push" {
                return die("HEAD changed since the push checkpoint -- start a new push");
            }
            if !is_ancestor(&self.head, &now.head) {
                return die("HEAD no longer descends from the checkpoint -- start a new operation");
            }
            let changed = git(&["diff", "--name-only", "-z", &self.head, &now.head])
                .bytes()
                .ok_or(Fail::Hard)?;
            if nul_fields(&changed).iter().any(|p| {
                p == STATE_FILE
                    || p.ends_with(&format!("/{STATE_FILE}"))
                    || p == crate::config::FILE
                    || p.ends_with(&format!("/{}", crate::config::FILE))
            }) {
                return die(
                    "splice configuration changed since the checkpoint -- start a new operation",
                );
            }
        }
        Ok(())
    }
}

#[derive(Default, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct ExecResult {
    rebuilt_commit: Option<String>,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Payload {
    #[serde(default)]
    hook_scope: String,
    version: u32,
    operation: String,
    sequence: u64,
    event: Event,
    repository: Repository,
    continuation: Continuation,
    #[serde(default)]
    result: ExecResult,
}

fn hook(command: &str, scope: &str, payload: &Payload) -> Res<()> {
    let mut input = serde_json::to_vec(payload).map_err(|_| Fail::Hard)?;
    input.push(b'\n');
    let mut child = match Command::new("sh")
        .args(["-c", command])
        .current_dir(std::path::Path::new(&payload.repository.root).join(scope))
        .stdin(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(error) => return die(format!("--exec: {error}")),
    };
    let mut stdin = child.stdin.take().ok_or(Fail::Hard)?;
    let writer = std::thread::spawn(move || stdin.write_all(&input));
    let status = child.wait().map_err(|_| Fail::Hard)?;
    let written = writer.join().map_err(|_| Fail::Hard)?;
    if !status.success() {
        log_err(format!("--exec stopped at checkpoint {} -- save its payload and use --continue-from to continue", payload.sequence));
        let (verb, remaining) = match &payload.continuation.pushes {
            Some(pushes) => ("pushed", pushes.remaining()),
            None => ("pulled", payload.continuation.merges.remaining()),
        };
        if !remaining.is_empty() {
            log_err(format!("Not {verb} yet: {}", remaining.join(" ")));
        }
        return Err(Fail::Hard);
    }
    if let Err(error) = written {
        if error.kind() != std::io::ErrorKind::BrokenPipe {
            return die(format!("--exec: could not send payload: {error}"));
        }
    }
    payload.repository.validate(&payload.operation)?;
    if payload.operation == "pull" {
        require_no_splice_in_progress()
    } else {
        Ok(())
    }
}

pub fn run(context: &mut ExecutionContext, operation: &str, args: Args) -> Res<i32> {
    let enabled = if !args.continue_from.is_empty() {
        true
    } else if let Some(invocation) = &args.configuration {
        !args.exec.is_empty() || context.configuration.has_hooks(invocation, "HEAD")?
    } else {
        !args.exec.is_empty()
    };
    crate::util::checkpoint_output(enabled);
    context.checkpointing = true;
    let result = run_inner(context, operation, args);
    context.checkpointing = false;
    crate::util::checkpoint_output(false);
    result
}

fn prepare<'context>(
    context: &'context mut ExecutionContext,
    operation: &str,
    args: Args,
) -> Res<Repo<'context>> {
    if args.has_flag("--rebase") {
        return die("--exec and --continue-from do not support --rebase yet");
    }
    args.require_one_splice_for_message()?;
    args.require_branch_for_track()?;
    let mut repo = Repo::new(context, args);
    if operation == "pull" {
        apply_merge_options(&mut repo)?;
    }
    repo.open()?;
    if operation == "pull" {
        require_no_splice_in_progress()?;
        repo.require_message_template(Message {
            command: "pull",
            upstream: KNOWN,
            old: KNOWN,
            new: KNOWN,
            ..Message::default()
        })?;
    }
    Ok(repo)
}

fn run_inner(context: &mut ExecutionContext, operation: &str, args: Args) -> Res<i32> {
    let command = args.exec.clone();
    let (mut repo, mut state, mut sequence, first_event) = if args.continue_from.is_empty() {
        let mut repo = prepare(context, operation, args)?;
        let mut pushes = None;
        let (branch, fetched, failures, phase) = if operation == "push" {
            pushes = Some(crate::push::PushProgress::new(&mut repo)?);
            (
                repo.monorepo_branch.clone(),
                Vec::new(),
                Vec::new(),
                Phase::Pushing,
            )
        } else if operation == "fetch" {
            let (branch, failures) = crate::fetch::fetch_for_command(&mut repo)?;
            repo.monorepo_branch = branch.clone();
            (branch, Vec::new(), failures, Phase::Tracking)
        } else {
            repo.select_splices(Kind::Explicit, "pull")?;
            let branch = repo.monorepo_branch.clone();
            let (fetched, failures) = crate::pull::fetch_for_pull(&mut repo)?;
            (branch, fetched, failures, Phase::Merging)
        };
        let fold_start = if operation == "pull" && crate::pull::should_fold(&mut repo)? {
            if !git(&["merge-base", "--is-ancestor", "SPLICE_PULL_START", "HEAD"])
                .q()
                .ok()
                && !git(&["update-ref", "SPLICE_PULL_START", "HEAD"]).ok()
            {
                return die("SPLICE_PULL_START couldn't be updated");
            }
            commit_of("SPLICE_PULL_START")
        } else {
            None
        };
        let event = (operation != "push").then(|| Event::AfterFetch {
            fetched: std::mem::take(&mut repo.fetch_checkpoint),
        });
        let state = Continuation {
            pending_hooks: Vec::new(),
            pending_event: None,
            cli_hook: !repo.args.exec.is_empty(),
            args: repo.args.clone(),
            branch,
            fold_start,
            fold_roots: crate::pull::fold_roots(&repo),
            fetch_failures: failures,
            merges: MergeProgress::new(&fetched),
            phase,
            discovery: Discovery::capture(&repo),
            pushes,
        };
        (repo, state, 0, event)
    } else {
        if args.all
            || !args.paths.is_empty()
            || !args.upstream.is_empty()
            || !args.branch.is_empty()
            || !args.message.is_empty()
            || !args.message_template.is_empty()
            || !args.rebuilt_commit.is_empty()
            || !args.flags.is_empty()
        {
            return die(
                "--continue-from restores the operation's options -- only --exec may be supplied again",
            );
        }
        let mut bytes = Vec::new();
        if args.continue_from == "-" {
            std::io::stdin()
                .take(16 * 1024 * 1024 + 1)
                .read_to_end(&mut bytes)
                .map_err(|_| Fail::Hard)?;
        } else {
            let file = match std::fs::File::open(&args.continue_from) {
                Ok(file) => file,
                Err(error) => return die(format!("--continue-from: {error}")),
            };
            file.take(16 * 1024 * 1024 + 1)
                .read_to_end(&mut bytes)
                .map_err(|_| Fail::Hard)?;
        }
        if bytes.len() > 16 * 1024 * 1024 {
            return die("continuation payload is too large");
        }
        let payload: Payload = match serde_json::from_slice(&bytes) {
            Ok(payload) => payload,
            Err(error) => {
                return die(format!(
                    "invalid continuation payload: {error}{}",
                    if command.is_empty() {
                        "; a command-line checkpoint needs --exec again"
                    } else {
                        ""
                    }
                ))
            }
        };
        if payload.version != 1 || payload.operation != operation {
            return die("unsupported continuation version or operation");
        }
        if (operation == "fetch") != matches!(payload.continuation.phase, Phase::Tracking)
            || (operation == "push") != matches!(payload.continuation.phase, Phase::Pushing)
            || (operation == "push") != payload.continuation.pushes.is_some()
        {
            return die("inconsistent continuation phase for operation");
        }
        if payload.result.rebuilt_commit.is_some()
            && (operation != "push" || !matches!(payload.event, Event::AfterRebuild(_)))
        {
            return die("rebuilt_commit result requires a push after-rebuild checkpoint");
        }
        if command.is_empty()
            && (payload.continuation.cli_hook || payload.continuation.args.configuration.is_none())
        {
            return die("--continue-from needs --exec again for its command-line hook");
        }
        let mut saved_args = payload.continuation.args.clone();
        saved_args.exec = command.clone();
        if let Some(invocation) = &mut saved_args.configuration {
            invocation.cli.exec = command.clone();
        }
        let mut repo = prepare(context, operation, saved_args)?;
        payload.repository.validate(&payload.operation)?;
        if payload.continuation.branch != payload.repository.branch
            || (operation == "pull"
                && payload.continuation.fold_start.is_some()
                && payload.continuation.fold_start != payload.repository.fold_start)
        {
            return die("inconsistent continuation payload");
        }
        repo.monorepo_branch = payload.continuation.branch.clone();
        payload.continuation.discovery.clone().restore(&mut repo);
        let mut state = payload.continuation;
        if state.fold_roots.is_empty() {
            state.fold_roots = crate::pull::fold_roots(&repo);
        }
        if let Some(commit) = payload.result.rebuilt_commit {
            state
                .pushes
                .as_mut()
                .ok_or(Fail::Hard)?
                .replace_rebuild(&mut repo, &commit)?;
        }
        let pending = if state.pending_hooks.is_empty() {
            None
        } else {
            Some(state.pending_event.take().unwrap_or(payload.event))
        };
        (repo, state, payload.sequence, pending)
    };

    let mut event = first_event;
    loop {
        if let Some(event) = event.take() {
            let mut scheduled = if state.pending_hooks.is_empty() {
                crate::config::schedule(&mut repo, &event)?
            } else {
                std::mem::take(&mut state.pending_hooks)
            };
            while !scheduled.is_empty() {
                let next = scheduled.remove(0);
                state.pending_hooks = scheduled.clone();
                state.pending_event = (!scheduled.is_empty()).then(|| event.clone());
                sequence = sequence.checked_add(1).ok_or(Fail::Hard)?;
                state.discovery = Discovery::capture(&repo);
                let (handler, scope) = repo.context.configuration.command(&next.hook, &command)?;
                let mut scoped_event = event.clone();
                if let Event::AfterFetch { fetched } = &mut scoped_event {
                    fetched.retain(|entry| next.paths.contains(&entry.path));
                }
                crate::util::checkpoint_output(true);
                let payload = Payload {
                    hook_scope: scope.clone(),
                    version: 1,
                    operation: operation.into(),
                    sequence,
                    event: scoped_event,
                    repository: Repository::capture()?,
                    continuation: state.clone(),
                    result: ExecResult::default(),
                };
                hook(&handler, &scope, &payload)?;
                repo.uncommitted.clear();
            }
        }
        match state.phase {
            Phase::Pushing => {
                let pushes = state.pushes.as_mut().ok_or(Fail::Hard)?;
                if pushes.done() {
                    return pushes.finish();
                }
                event = pushes.advance(&mut repo, &state.branch)?;
            }
            Phase::Tracking => {
                if operation != "fetch" {
                    return die("inconsistent continuation phase for pull");
                }
                return crate::fetch::finish_fetch(&mut repo, &state.branch, &state.fetch_failures);
            }
            Phase::Merging => {
                if !state.merges.done() {
                    event = state.merges.advance(&mut repo, &state.branch, "pull")?;
                    continue;
                }
                state.merges.finish("pull")?;
                if !state.fetch_failures.is_empty() {
                    log_err(format!("Not fetched: {}", state.fetch_failures.join(" ")));
                    return Ok(1);
                }
                if state.fold_start.is_some() {
                    state.phase = Phase::Fold;
                    event = Some(Event::BeforeFold);
                } else {
                    state.phase = Phase::Done;
                }
            }
            Phase::Fold => {
                crate::pull::fold_pulls(&state.fold_roots)?;
                if !git(&["update-ref", "-d", "SPLICE_PULL_START"]).ok() {
                    return die("SPLICE_PULL_START couldn't be removed");
                }
                state.fold_start = None;
                state.phase = Phase::Done;
                event = Some(Event::AfterFold);
            }
            Phase::Done => return Ok(0),
        }
    }
}
