//! git splice pull.

use crate::args::parse_args;
use crate::context::ExecutionContext;
use crate::execution::{Execution, ExecutionEvent, ExecutionOutcome, Operation};
use crate::fetch::{FetchPlan, FetchResults};
use crate::merge::{apply_merge_options, MergeProgress, MERGE_OPTIONS};
use crate::message::{Message, KNOWN};
use crate::repo::*;
use crate::tree::{SpliceTree, Task, Tasks};
use crate::util::*;

pub const USAGE: &str = include_str!("usage/pull.txt");

pub fn run(context: &mut ExecutionContext, argv: &[String]) -> Res<i32> {
    start(context, argv)?.run()
}

/// Starts a pull retained in memory until it is completed or dropped.
pub fn start<'context>(
    context: &'context mut ExecutionContext,
    argv: &[String],
) -> Res<PullExecution<'context>> {
    let args = parse_args(USAGE, &format!("{MERGE_OPTIONS} --recursive --exec"), argv)?;
    args.require_one_splice_for_message()?;
    args.require_branch_for_track()?;
    let mut repo = Repo::new(context, args);
    apply_merge_options(&mut repo)?;
    repo.open()?;
    let progress = PullProgress::new(&mut repo)?;
    Ok(PullExecution {
        inner: Execution::new(repo, progress)?,
    })
}

/// A pull retained across inspection-only pauses in the same process.
pub struct PullExecution<'context> {
    inner: Execution<'context, PullProgress>,
}

impl PullExecution<'_> {
    pub fn run(&mut self) -> Res<i32> {
        self.inner.run()
    }

    /// The splice tree at HEAD, with what this pull did and still does for each
    /// splice: see [`SpliceTree::render`].
    pub fn splice_tree(&mut self) -> Res<SpliceTree> {
        self.inner.splice_tree()
    }

    /// Pauses at a selected event. Repository identity, HEAD, branch, fetched
    /// refs, configuration, tracked files, index and pull markers must remain
    /// unchanged in the predicate and while paused.
    pub fn run_until(
        &mut self,
        stop: impl FnMut(&ExecutionEvent) -> bool,
    ) -> Res<ExecutionOutcome> {
        self.inner.run_until(stop)
    }
}

enum PullPhase {
    Fetch(FetchPlan),
    Fetched(FetchResults),
    Reported,
    Merge(Box<MergeProgress>),
    Finalize,
    Fold { observed_head: Option<String> },
    Cleanup { allowed: bool },
    Done,
}

struct PullProgress {
    branch: String,
    selected: Vec<String>,
    recursive: bool,
    rebase_tree: bool,
    resumed_rebase: bool,
    fold_roots: Vec<String>,
    rebasing: bool,
    fetch_failures: Vec<String>,
    status: i32,
    phase: PullPhase,
}

impl PullProgress {
    fn new(repo: &mut Repo) -> Res<Self> {
        repo.require_message_template(Message {
            command: "pull",
            upstream: KNOWN,
            old: KNOWN,
            new: KNOWN,
            ..Message::default()
        })?;
        // Before select_splices: a rebase in progress has detached HEAD.
        require_no_splice_in_progress()?;
        let recursive = repo.args.has_flag("--recursive") || repo.args.all;
        let rebase_tree = recursive && repo.merge_rebase;
        let resumed = rebase_under_way()?;
        if let Some(branch) = &resumed {
            if !rebase_tree {
                return die(format!(
                "a 'pull --rebase --recursive' is under way for '{branch}' -- re-run it, or 'git switch {branch}' to give up"
            ));
            }
            repo.monorepo_branch = branch.clone();
        }
        // The splices pull below, top-down, rather than rebasing onto each pull.
        repo.merge_rebase = repo.merge_rebase && !recursive;
        repo.select_splices(Kind::Explicit, "pull")?;
        let branch = repo.monorepo_branch.clone();
        let selected = repo.selected.clone();

        // A splice below one selected, selected itself or not: a pull above can
        // move its synced commit.
        let below_selected = |path: &str| {
            selected
                .iter()
                .any(|above| path.starts_with(&format!("{above}/")))
        };
        let top: Vec<String> = selected
            .iter()
            .filter(|path| !below_selected(path))
            .cloned()
            .collect();
        let below: Vec<String> = repo
            .all_paths
            .iter()
            .filter(|path| below_selected(path))
            .cloned()
            .collect();
        let mut entries = repo.used_upstream_entry(&top);
        entries.extend(repo.every_upstream_entry(&below)?);
        let plan = repo.prepare_fetch(&branch, &entries)?;
        Ok(Self {
            branch,
            selected,
            recursive,
            rebase_tree,
            resumed_rebase: resumed.is_some(),
            fold_roots: Vec::new(),
            rebasing: false,
            fetch_failures: Vec::new(),
            status: 0,
            phase: PullPhase::Fetch(plan),
        })
    }

    fn done(&self) -> bool {
        matches!(self.phase, PullPhase::Done)
    }

    fn advance(&mut self, repo: &mut Repo) -> Res<Option<ExecutionEvent>> {
        match std::mem::replace(&mut self.phase, PullPhase::Done) {
            PullPhase::Done => Ok(None),
            PullPhase::Fetch(plan) => {
                self.phase = PullPhase::Fetched(plan.download());
                Ok(None)
            }
            PullPhase::Fetched(results) => {
                let (failures, event) = results.finish(repo)?;
                self.fetch_failures = failures;
                self.phase = PullPhase::Reported;
                Ok(Some(event))
            }
            PullPhase::Reported => self.begin_merges(repo).map(|()| None),
            PullPhase::Merge(mut merges) => {
                let advanced = merges.advance_event(repo);
                let event = advanced.as_ref().ok().cloned().flatten();
                if advanced.is_err() {
                    self.status = 1;
                    self.phase = PullPhase::Finalize;
                } else if merges.done() {
                    if merges.finish().is_err() {
                        self.status = 1;
                    }
                    self.phase = PullPhase::Finalize;
                } else {
                    self.phase = PullPhase::Merge(merges);
                }
                Ok(event)
            }
            PullPhase::Finalize => {
                let allowed = self.recursive && !splice_in_progress();
                if allowed && self.status == 0 {
                    let observed_head = commit_of("HEAD");
                    let event = observed_head
                        .as_ref()
                        .map(|head| ExecutionEvent::BeforeFold {
                            roots: self.fold_roots.clone(),
                            head: head.clone(),
                        });
                    self.phase = PullPhase::Fold { observed_head };
                    Ok(event)
                } else {
                    self.phase = PullPhase::Cleanup { allowed };
                    Ok(None)
                }
            }
            PullPhase::Fold { observed_head } => {
                fold_pulls(&self.fold_roots)?;
                let event =
                    observed_head
                        .zip(commit_of("HEAD"))
                        .map(|(head_before, head_after)| ExecutionEvent::AfterFold {
                            roots: self.fold_roots.clone(),
                            head_before,
                            head_after,
                        });
                self.phase = PullPhase::Cleanup { allowed: true };
                Ok(event)
            }
            PullPhase::Cleanup { allowed } => self.finalize(allowed).map(|()| None),
        }
    }

    fn begin_merges(&mut self, repo: &mut Repo) -> Res<()> {
        let mut fetched = Vec::new();
        for path in &self.selected {
            if self.fetch_failures.contains(path) {
                continue;
            }
            if let Some(failed) = first_above(path, &self.fetch_failures) {
                log_err(format!(
                    "{path}: not pulled, since {failed} above it wasn't fetched"
                ));
                continue;
            }
            // Its pull could move the synced commit of the failed one to one that
            // wasn't fetched.
            if let Some(failed) = first_below(path, &self.fetch_failures) {
                log_err(format!(
                "{path}: not pulled, since {failed} below it wasn't fetched -- 'git splice merge {path}' merges what was fetched anyway"
            ));
                continue;
            }
            fetched.push(path.clone());
        }

        // A recursive pull is one commit per splice it starts from, made of its
        // pulls once the last run ends without a conflict; pull --all starts
        // from each splice no other is around. A run that stops leaves where it
        // started, which a later run goes on from only while HEAD still descends
        // from it: not after the branch was reset past it, e.g. after an abort.
        let fold = self.recursive;
        let tops: Vec<String> = if repo.args.all {
            repo.all_paths
                .iter()
                .filter(|path| first_above(path, &repo.all_paths).is_none())
                .cloned()
                .collect()
        } else {
            repo.args
                .paths
                .iter()
                .map(|path| normalize_path(path))
                .collect()
        };
        let goes_on = git(&["merge-base", "--is-ancestor", START, "HEAD"])
            .q()
            .ok();
        let mut rewinds = false;
        if self.rebase_tree && !self.resumed_rebase {
            for path in &fetched {
                if repo.pull_to_rebase(path, &self.branch)? {
                    rewinds = true;
                }
            }
        }
        if rewinds {
            rewind_to_last_pull(&tops, &self.branch)?;
        } else if fold && !goes_on && !git(&["update-ref", START, "HEAD"]).ok() {
            return fail(format!("{START} couldn't be updated"));
        }
        self.rebasing = rebase_under_way()?.is_some();
        self.fold_roots = tops;
        self.phase = if fetched.is_empty() {
            PullPhase::Finalize
        } else {
            PullPhase::Merge(Box::new(MergeProgress::new(
                repo,
                &self.branch,
                "pull",
                &fetched,
            )))
        };
        Ok(())
    }

    fn finalize(&mut self, allowed: bool) -> Res<()> {
        if allowed && (self.status == 0 || !self.fetch_failures.is_empty()) {
            if self.rebasing {
                if !replay_own_commits(&self.branch)? {
                    self.status = 1;
                }
            } else if !git(&["update-ref", "-d", START]).ok() {
                return fail(format!("{START} couldn't be updated"));
            }
        }
        self.say_if_detached()?;
        if !self.fetch_failures.is_empty() {
            log_err(format!("Not fetched: {}", self.fetch_failures.join(" ")));
            self.status = 1;
        }
        Ok(())
    }

    fn say_if_detached(&self) -> Res<()> {
        if self.rebasing && rebase_under_way()?.is_some() {
            let branch = &self.branch;
            log_err(format!(
            "The pulls are on a detached HEAD, '{branch}' is as it was -- re-run pull to go on, or 'git switch {branch}' to give up"
        ));
        }
        Ok(())
    }

    fn finish(&self) -> Res<i32> {
        if !self.done() {
            return die("pull still has pending work");
        }
        Ok(self.status)
    }
}

const START: &str = "SPLICE_PULL_START";
/// The branch a pull --rebase --recursive rebases once the pulls are done,
/// while they're made on a detached HEAD.
const REBASING: &str = "SPLICE_PULL_BRANCH";

/// The branch whose pull --rebase --recursive goes on: its pulls are on a
/// detached HEAD that still descends from where they started. Forgets one
/// that doesn't, e.g. after 'git switch' gave it up.
fn rebase_under_way() -> Res<Option<String>> {
    let Some(branch) = git(&["symbolic-ref", "--quiet", "--short", REBASING])
        .q()
        .out()
    else {
        return Ok(None);
    };
    let detached = git(&["symbolic-ref", "--quiet", "HEAD"])
        .q()
        .out()
        .is_none();
    let goes_on = git(&["merge-base", "--is-ancestor", START, "HEAD"])
        .q()
        .ok();
    if detached && goes_on {
        return Ok(Some(branch));
    }
    forget_rebase()?;
    Ok(None)
}

fn forget_rebase() -> Res<()> {
    let _ = git(&["symbolic-ref", "--delete", REBASING]).q().ok();
    if git(&["rev-parse", "--quiet", "--verify", START]).q().ok()
        && !git(&["update-ref", "-d", START]).ok()
    {
        return fail(format!("{START} couldn't be updated"));
    }
    Ok(())
}

/// For pull --rebase --recursive: detaches HEAD at the newest first-parent
/// commit that changed a .splice in or below <tops>, so the pulls go there,
/// and the commits since, the monorepo's own, are rebased onto them once.
/// Rebasing onto each pull instead would replay the pulls of the splices
/// above it too.
fn rewind_to_last_pull(tops: &[String], branch: &str) -> Res<()> {
    let mut args = vec![
        "log".to_string(),
        "--first-parent".to_string(),
        "-1".to_string(),
        "--format=%H".to_string(),
        "--".to_string(),
    ];
    for top in tops {
        args.push(format!(":(glob){top}/**/{STATE_FILE}"));
    }
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    let Some(base) = git(&args).out().filter(|base| !base.is_empty()) else {
        return fail("no pull to rebase onto");
    };
    let head = git(&["rev-parse", "HEAD"]).out().unwrap_or_default();
    if base == head {
        return if git(&["update-ref", START, "HEAD"]).ok() {
            Ok(())
        } else {
            fail(format!("{START} couldn't be updated"))
        };
    }
    let since = format!("{base}..HEAD");
    let merges = git(&["rev-list", "--min-parents=2", "--count", &since])
        .out()
        .unwrap_or_default();
    if merges != "0" {
        return fail(format!(
            "there's a merge commit since the last pull, {}, whose own changes --rebase would drop -- pull without --rebase",
            short(&base)
        ));
    }
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
            "'{published}' has commits since the last pull, {}, which --rebase would rewrite -- pull on a branch nobody else has, e.g. a pull request's",
            short(&base)
        ));
    }
    if !git(&["diff-index", "--quiet", "HEAD", "--"]).ok() {
        return fail("the work tree has changes -- commit or stash them, then pull --rebase");
    }
    if !git(&["update-ref", START, &base]).ok()
        || !git(&["symbolic-ref", REBASING, &format!("refs/heads/{branch}")]).ok()
    {
        return fail(format!("{START} couldn't be updated"));
    }
    if !git(&["checkout", "-q", "--detach", &base]).ok() {
        forget_rebase()?;
        return fail(format!("HEAD couldn't be detached at {}", short(&base)));
    }
    Ok(())
}

/// Rebases <branch>'s commits since the pulls started onto the pulls, and
/// checks it out. False if the rebase stopped at a conflict.
fn replay_own_commits(branch: &str) -> Res<bool> {
    let Some(base) = git(&["rev-parse", START]).out() else {
        return fail(format!("{START} couldn't be read"));
    };
    let pulled = git(&["rev-parse", "HEAD"]).out().unwrap_or_default();
    forget_rebase()?;
    let count = git(&["rev-list", "--count", &format!("{base}..{branch}")])
        .out()
        .unwrap_or_default();
    if pulled == base {
        if !git(&["checkout", "-q", branch]).ok() {
            return fail(format!("'{branch}' couldn't be checked out"));
        }
        return Ok(true);
    }
    let rebased = git(&[
        "-c",
        "advice.mergeConflict=false",
        "rebase",
        "-q",
        "--no-update-refs",
        "--no-autostash",
        "--onto",
        &pulled,
        &base,
        branch,
    ])
    .run();
    if rebased != 0 {
        if rebase_in_progress() {
            log_err(
                "conflict while rebasing onto the pull -- resolve it, then 'git rebase --continue' (or 'git rebase --abort' to give up)",
            );
            return Ok(false);
        }
        return fail(format!(
            "git rebase didn't start, see above -- the pulls are at {}",
            short(&pulled)
        ));
    }
    let plural = if count == "1" { "" } else { "s" };
    log_ok(format!(
        "rebased {count} commit{plural} of '{branch}' onto the pull"
    ));
    Ok(true)
}

/// The .splice files commit <commit> changes.
fn changed_state_files(commit: &str) -> Vec<String> {
    let changed = git(&[
        "diff-tree",
        "-z",
        "--no-commit-id",
        "--name-only",
        "-r",
        commit,
    ])
    .bytes()
    .unwrap_or_default();
    nul_fields(&changed)
        .into_iter()
        .filter(|file| file == STATE_FILE || file.ends_with(&format!("/{STATE_FILE}")))
        .collect()
}

/// <message> without the list of conflicted files Git adds to it, which a
/// commit made with --no-edit after a conflict keeps. Other lines starting
/// with '#' are the message's own, e.g. from a template.
fn without_conflicts(message: &str) -> String {
    let all: Vec<&str> = message.lines().collect();
    let mut lines = Vec::new();
    let mut in_list = false;
    for (i, line) in all.iter().enumerate() {
        let lists_files = all.get(i + 1).is_some_and(|next| next.starts_with("#\t"));
        if *line == "# Conflicts:" && lists_files {
            in_list = true;
        } else if in_list && (*line == "#" || line.starts_with("#\t")) {
        } else {
            in_list = false;
            lines.push(*line);
        }
    }
    lines.join("\n").trim().to_string()
}

/// Makes the pulls since the recursive pull started one commit per splice
/// in <tops> it started from, each made of the pulls in and below it, if
/// every commit since is such a pull, and the pulls of each come one after
/// another. Its message is the message of that splice's own pull, followed
/// by the messages of the pulls below it.
fn fold_pulls(tops: &[String]) -> Res<()> {
    let range = format!("{START}..HEAD");
    let commits: Vec<String> = git(&["rev-list", "--reverse", "--first-parent", &range])
        .out()
        .unwrap_or_default()
        .lines()
        .map(str::to_string)
        .collect();
    let mut groups: Vec<(String, Vec<String>)> = Vec::new();
    for commit in &commits {
        let changed = changed_state_files(commit);
        let top = tops.iter().find(|top| {
            changed
                .iter()
                .any(|file| file.starts_with(&format!("{top}/")))
        });
        let Some(top) = top else {
            log_warn(format!(
                "{} isn't a pull -- the pulls since the recursive pull started stay separate commits",
                short(commit)
            ));
            return Ok(());
        };
        if let Some((_, group)) = groups.last_mut().filter(|(last, _)| last == top) {
            group.push(commit.clone());
        } else if groups.iter().any(|(other, _)| other == top) {
            log_warn(format!(
                "{} pulls {top} after another splice -- the pulls since the recursive pull started stay separate commits",
                short(commit)
            ));
            return Ok(());
        } else {
            groups.push((top.clone(), vec![commit.clone()]));
        }
    }
    if groups.iter().all(|(_, group)| group.len() < 2) {
        return Ok(());
    }
    let message_of = |commit: &str| {
        without_conflicts(
            &git(&["log", "-1", "--format=%B", commit])
                .out()
                .unwrap_or_default(),
        )
    };
    let Some(mut parent) = git(&["rev-parse", START]).out() else {
        return fail(format!("{START} couldn't be read"));
    };
    let mut made = Vec::new();
    for (top, group) in &groups {
        let own = format!("{top}/{STATE_FILE}");
        let pulled_itself = changed_state_files(&group[0]).contains(&own);
        let (head, below) = if pulled_itself {
            (message_of(&group[0]), &group[1..])
        } else {
            (
                format!("splice: pull {top} and the splices in it"),
                &group[..],
            )
        };
        let below: Vec<String> = below.iter().map(|c| message_of(c)).collect();
        let joint = if below.iter().any(|m| m.contains('\n')) {
            "\n\n"
        } else {
            "\n"
        };
        let message = if below.is_empty() {
            format!("{head}\n")
        } else {
            format!("{head}\n\n{}\n", below.join(joint))
        };
        let tree = format!("{}^{{tree}}", group[group.len() - 1]);
        let Some(folded) = git(&["commit-tree", &tree, "-p", &parent, "-m", &message]).out() else {
            return fail("the pulls couldn't be made one commit");
        };
        if group.len() > 1 {
            made.push((top.clone(), group.len(), folded.clone()));
        }
        parent = folded;
    }
    let head = git(&["rev-parse", "HEAD"]).out().unwrap_or_default();
    if !git(&[
        "update-ref",
        "-m",
        "splice: fold a recursive pull",
        "HEAD",
        &parent,
        &head,
    ])
    .ok()
    {
        return fail("the pulls couldn't be made one commit");
    }
    for (top, count, folded) in made {
        log_ok(format!(
            "{top}: {count} pulls made one commit, {}",
            short(&folded)
        ));
    }
    Ok(())
}

impl Operation for PullProgress {
    const NAME: &'static str = "pull";
    const CHECK_TRACKED_STATE: bool = true;

    fn done(&self) -> bool {
        PullProgress::done(self)
    }
    fn advance(&mut self, repo: &mut Repo) -> Res<Option<ExecutionEvent>> {
        PullProgress::advance(self, repo)
    }
    fn finish(&self) -> Res<i32> {
        PullProgress::finish(self)
    }
    fn stopped(&self) {
        let _ = self.say_if_detached();
    }
    fn tasks(&self) -> Tasks {
        let pending = |step| {
            self.selected
                .iter()
                .map(|path| (path.clone(), Task::Pending(step)))
                .collect()
        };
        match &self.phase {
            PullPhase::Fetch(_) => Tasks {
                per_splice: pending("fetch"),
                next: None,
            },
            PullPhase::Fetched(_) | PullPhase::Reported => Tasks {
                per_splice: pending("merge"),
                next: None,
            },
            PullPhase::Merge(merges) => Tasks {
                per_splice: merges.tasks(),
                next: None,
            },
            PullPhase::Finalize | PullPhase::Fold { .. } => Tasks {
                per_splice: Vec::new(),
                next: self.recursive.then_some("fold"),
            },
            PullPhase::Cleanup { .. } => Tasks {
                per_splice: Vec::new(),
                next: Some("clean up"),
            },
            PullPhase::Done => Tasks::default(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::util::test_repo::{git, with_repository};

    struct FileVersions {
        before: &'static str,
        after: &'static str,
    }

    struct SpliceFixture {
        path: &'static str,
        upstream: &'static str,
        file: FileVersions,
    }

    struct NestedFixture {
        parent: SpliceFixture,
        child: SpliceFixture,
    }

    struct Updates {
        parent: String,
        child: String,
        parent_before: String,
        child_before: String,
        parent_ref: String,
        child_ref: String,
    }

    fn setup_nested_updates(context: &mut ExecutionContext, fixture: &NestedFixture) -> Updates {
        let parent = &fixture.parent;
        let child = &fixture.child;
        git(&["config", "user.name", "Test"]);
        git(&["config", "user.email", "test@example.com"]);
        git(&["commit", "--allow-empty", "-qm", "initial"]);
        git(&["init", "-q", "--initial-branch=main", child.upstream]);
        std::fs::write(format!("{}/file", child.upstream), child.file.before).unwrap();
        git(&["-C", child.upstream, "add", "."]);
        git(&["-C", child.upstream, "commit", "-qm", "initial child"]);
        let child_before = git(&["-C", child.upstream, "rev-parse", "HEAD"]);
        git(&["init", "-q", "--initial-branch=main", parent.upstream]);
        let inside = std::path::Path::new(child.path)
            .strip_prefix(parent.path)
            .unwrap();
        let nested = std::path::Path::new(parent.upstream).join(inside);
        std::fs::create_dir_all(&nested).unwrap();
        std::fs::write(format!("{}/file", parent.upstream), parent.file.before).unwrap();
        std::fs::write(nested.join("file"), child.file.before).unwrap();
        let root = std::env::current_dir().unwrap();
        std::fs::write(
            nested.join(".splice"),
            format!(
                "[splice]\n id = {}\n commit = {child_before}\n[upstream \"origin\"]\n url = {}\n",
                child.upstream,
                root.join(child.upstream).display()
            ),
        )
        .unwrap();
        git(&["-C", parent.upstream, "add", "."]);
        git(&["-C", parent.upstream, "commit", "-qm", "initial parent"]);
        let parent_before = git(&["-C", parent.upstream, "rev-parse", "HEAD"]);
        crate::clone::run(
            context,
            &[
                root.join(parent.upstream).to_string_lossy().into_owned(),
                parent.path.into(),
            ],
        )
        .unwrap();
        std::fs::write(format!("{}/file", parent.upstream), parent.file.after).unwrap();
        git(&["-C", parent.upstream, "commit", "-qam", "update parent"]);
        std::fs::write(format!("{}/file", child.upstream), child.file.after).unwrap();
        git(&["-C", child.upstream, "commit", "-qam", "update child"]);
        let mut repo = Repo::new(context, Default::default());
        repo.open().unwrap();
        repo.select_paths(Kind::Overview, "fetch").unwrap();
        Updates {
            parent: git(&["-C", parent.upstream, "rev-parse", "HEAD"]),
            child: git(&["-C", child.upstream, "rev-parse", "HEAD"]),
            parent_before,
            child_before,
            parent_ref: repo.splice_ref(parent.path, "main"),
            child_ref: repo.splice_ref(child.path, "main"),
        }
    }

    fn nested_updates(context: &mut ExecutionContext) -> Updates {
        setup_nested_updates(
            context,
            &NestedFixture {
                parent: SpliceFixture {
                    path: "vendor/a",
                    upstream: "parent",
                    file: FileVersions {
                        before: "old parent\n",
                        after: "new parent\n",
                    },
                },
                child: SpliceFixture {
                    path: "vendor/a/b",
                    upstream: "child",
                    file: FileVersions {
                        before: "old child\n",
                        after: "new child\n",
                    },
                },
            },
        )
    }

    fn assert_pull_diagram(
        checkpoint: &str,
        fixture: &NestedFixture,
        updates: &Updates,
        start: &str,
        names: &[(&str, &str)],
        expected: &str,
    ) {
        let label = |id: &str| {
            if id.is_empty() {
                return "-".to_string();
            }
            names
                .iter()
                .find(|(_, known)| *known == id)
                .map(|(name, _)| (*name).to_string())
                .unwrap_or_else(|| id.to_string())
        };
        let branch = git(&["rev-parse", "--abbrev-ref", "HEAD"]);
        let head = label(&git(&["rev-parse", "HEAD"]));
        let range = git(&[
            "rev-list",
            "--first-parent",
            "--reverse",
            &format!("{start}..HEAD"),
        ]);
        let mut history = vec![label(start)];
        history.extend(range.lines().map(label));
        let parent_fetched = label(&git(&["rev-parse", &updates.parent_ref]));
        let child_fetched = label(&git(&["rev-parse", &updates.child_ref]));
        let parent_record = label(&splice_config(fixture.parent.path, "commit", "HEAD"));
        let child_record = label(&splice_config(fixture.child.path, "commit", "HEAD"));
        let parent_file = std::fs::read_to_string(format!("{}/file", fixture.parent.path)).unwrap();
        let child_file = std::fs::read_to_string(format!("{}/file", fixture.child.path)).unwrap();
        let fold_start = label(&commit_of(START).unwrap_or_default());
        let diagram = format!("{branch} -> {head}\nhistory: {}\nfetched: a -> {parent_fetched}, a/b -> {child_fetched}\nrecorded: a -> {parent_record}, a/b -> {child_record}\nfiles: a = {parent_file:?}, a/b = {child_file:?}\nfold start -> {fold_start}", history.join(" -- "));
        println!("\n{checkpoint}\n{diagram}\n");
        assert_eq!(
            diagram, expected,
            "{checkpoint}: observed repository diagram:\n{diagram}"
        );
    }

    fn progress(context: &mut ExecutionContext) -> (Repo<'_>, PullProgress) {
        let args = parse_args(
            USAGE,
            "--recursive",
            &["--recursive".into(), "vendor/a".into()],
        )
        .unwrap();
        let mut repo = Repo::new(context, args);
        apply_merge_options(&mut repo).unwrap();
        repo.open().unwrap();
        let progress = PullProgress::new(&mut repo).unwrap();
        (repo, progress)
    }

    #[test]
    fn failing_exec_hook_leaves_downloads_applied_without_merging() {
        with_repository(|| {
            let mut context = ExecutionContext::new();
            let updates = nested_updates(&mut context);
            let head = git(&["rev-parse", "HEAD"]);
            assert_eq!(
                run(
                    &mut context,
                    &[
                        "--exec".into(),
                        r#"test "$GIT_SPLICE_EVENT" = after-fetch && test -z "$GIT_SPLICE_PATH$GIT_SPLICE_COMMIT" && exit 9"#.into(),
                        "vendor/a".into(),
                    ],
                ),
                Err(Fail::Code(9))
            );
            assert_eq!(git(&["rev-parse", "HEAD"]), head);
            assert_eq!(git(&["rev-parse", &updates.parent_ref]), updates.parent);
            assert_eq!(git(&["rev-parse", &updates.child_ref]), updates.child);
        });
    }

    /// Builds the state of the step-by-step scenario page from its setup.bash:
    /// a with b (with c inside) and d, then each upstream moves on and a
    /// splices e in. Leaves the current directory in the monorepo.
    fn step_by_step_scenario() {
        let docs = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("docs");
        let root = std::env::current_dir().unwrap();
        let mut config = vec![
            ("user.name".to_string(), "Test".to_string()),
            ("user.email".to_string(), "test@example.com".to_string()),
        ];
        for x in ["a", "b", "c", "d", "e"] {
            config.push((
                format!("url.{}/upstream-{x}.git.insteadOf", root.display()),
                format!("https://git.example.com/{x}.git"),
            ));
        }
        std::env::set_var("GIT_CONFIG_COUNT", config.len().to_string());
        for (index, (key, value)) in config.iter().enumerate() {
            std::env::set_var(format!("GIT_CONFIG_KEY_{index}"), key);
            std::env::set_var(format!("GIT_CONFIG_VALUE_{index}"), value);
        }
        let script = r#"
            set -euo pipefail
            source "$1"
            source "$2"
            scenario_recursive_pull "$PWD/monorepo" "$PWD/upstream"
            for x in b c d; do
              git clone -q "https://git.example.com/$x.git" "$x-work"
              echo "$x upstream" >>"$x-work/file.txt"
              git -C "$x-work" commit -q -am "${x}2: $x upstream"
              git -C "$x-work" push -q origin main
            done
            git clone -q https://git.example.com/a.git a-work
            add_splice a-work https://git.example.com/e.git e main "add e"
            echo "a upstream" >>a-work/file.txt
            git -C a-work commit -q --amend -am "a2: a upstream, and e spliced in"
            git -C a-work push -q origin main
        "#;
        let status =
            std::process::Command::new("bash")
                .args(["-c", script, "scenario"])
                .arg(docs.join("tests/helpers/fixtures.bash"))
                .arg(docs.join(
                    "09-scenarios/05-nested-splices/05-recursion/01-recursive-pull/setup.bash",
                ))
                .status()
                .unwrap();
        assert!(status.success());
        std::env::set_current_dir("monorepo").unwrap();
    }

    #[test]
    fn recursive_pull_shows_each_splices_commits_and_pending_work_step_by_step() {
        with_repository(|| {
            step_by_step_scenario();
            let mut named = vec![("s", git(&["rev-parse", "HEAD"]))];
            let mut context = ExecutionContext::new();
            let mut execution =
                start(&mut context, &["--recursive".into(), "vendor/a".into()]).unwrap();
            let tree = |execution: &mut PullExecution, named: &[(&str, String)]| {
                let tree = execution
                    .splice_tree()
                    .unwrap()
                    .render(crate::tree::labels(named));
                println!("{tree}");
                tree
            };
            let mut steps = vec![("start", tree(&mut execution, &named))];
            let wanted = |event: &ExecutionEvent| {
                matches!(
                    event,
                    ExecutionEvent::AfterFetch { .. }
                        | ExecutionEvent::AfterMerge { .. }
                        | ExecutionEvent::BeforeFold { .. }
                        | ExecutionEvent::AfterFold { .. }
                )
            };
            while let ExecutionOutcome::Paused(event) = execution.run_until(wanted).unwrap() {
                let step = match event {
                    ExecutionEvent::AfterMerge {
                        path, head_after, ..
                    } => {
                        let name = match path.rsplit('/').next().unwrap() {
                            "a" => "pa",
                            "b" => "pb",
                            "c" => "pc",
                            "d" => "pd",
                            other => panic!("unexpected merge of {other}"),
                        };
                        named.push((name, head_after));
                        "after-merge"
                    }
                    ExecutionEvent::AfterFetch { .. } => "after-fetch",
                    ExecutionEvent::BeforeFold { .. } => "before-fold",
                    ExecutionEvent::AfterFold { head_after, .. } => {
                        named.push(("p", head_after));
                        "after-fold"
                    }
                    _ => unreachable!(),
                };
                println!("{step}:");
                steps.push((step, tree(&mut execution, &named)));
            }
            let observed: String = steps
                .iter()
                .map(|(step, tree)| format!("{step}:\n{tree}"))
                .collect::<Vec<_>>()
                .join("\n");
            assert_eq!(
                observed,
                r#"start:
monorepo   H=s
vendor/a/  B=s  U=a1  R=a1  T=a1  pending: fetch
  b/       B=s  U=b1  R=b1  T=b1  pending: fetch
    c/     B=s  U=c1  R=c1  T=c1  pending: fetch
  d/       B=s  U=d1  R=d1  T=d1  pending: fetch

after-fetch:
monorepo   H=s
vendor/a/  B=s  U=a1  R=a1  T=a2  pending: merge
  b/       B=s  U=b1  R=b1  T=b2  pending: merge, after vendor/a/
    c/     B=s  U=c1  R=c1  T=c2  pending: merge, after b/
  d/       B=s  U=d1  R=d1  T=d2  pending: merge, after vendor/a/

after-merge:
monorepo   H=pa
vendor/a/  B=pa  U=a2  R=a2  T=a2  done
  b/       B=pa  U=b1  R=b1  T=b2  pending: merge
    c/     B=pa  U=c1  R=c1  T=c2  pending: merge, after b/
  d/       B=pa  U=d1  R=d1  T=d2  pending: merge
  e/       B=-   U=?   R=-   T=-

after-fetch:
monorepo   H=pa
vendor/a/  B=pa  U=a2  R=a2  T=a2  done
  b/       B=pa  U=b1  R=b1  T=b2  pending: merge
    c/     B=pa  U=c1  R=c1  T=c2  pending: merge, after b/
  d/       B=pa  U=d1  R=d1  T=d2  pending: merge
  e/       B=pa  U=e1  R=e1  T=e1  pending: merge

after-merge:
monorepo   H=pb
vendor/a/  B=pa  U=a2  R=pb'  T=a2  done
  b/       B=pb  U=b2  R=b2   T=b2  done
    c/     B=pb  U=c1  R=c1   T=c2  pending: merge
  d/       B=pa  U=d1  R=d1   T=d2  pending: merge
  e/       B=pa  U=e1  R=e1   T=e1  done

after-merge:
monorepo   H=pc
vendor/a/  B=pa  U=a2  R=pc'  T=a2  done
  b/       B=pb  U=b2  R=pc'  T=b2  done
    c/     B=pc  U=c2  R=c2   T=c2  done
  d/       B=pa  U=d1  R=d1   T=d2  pending: merge
  e/       B=pa  U=e1  R=e1   T=e1  done

after-merge:
monorepo   H=pd
vendor/a/  B=pa  U=a2  R=pd'  T=a2  done
  b/       B=pb  U=b2  R=pc'  T=b2  done
    c/     B=pc  U=c2  R=c2   T=c2  done
  d/       B=pd  U=d2  R=d2   T=d2  done
  e/       B=pa  U=e1  R=e1   T=e1  done

before-fold:
monorepo   H=pd
vendor/a/  B=pa  U=a2  R=pd'  T=a2
  b/       B=pb  U=b2  R=pc'  T=b2
    c/     B=pc  U=c2  R=c2   T=c2
  d/       B=pd  U=d2  R=d2   T=d2
  e/       B=pa  U=e1  R=e1   T=e1
next: fold

after-fold:
monorepo   H=p
vendor/a/  B=s  U=a2  R=p'  T=a2
  b/       B=s  U=b2  R=p'  T=b2
    c/     B=p  U=c2  R=c2  T=c2
  d/       B=p  U=d2  R=d2  T=d2
  e/       B=p  U=e1  R=e1  T=e1
next: clean up
"#,
                "observed trees:\n{observed}"
            );
        });
    }

    #[test]
    fn pull_rejects_state_changes_between_start_and_first_run() {
        with_repository(|| {
            let mut context = ExecutionContext::new();
            nested_updates(&mut context);
            let mut execution =
                start(&mut context, &["--recursive".into(), "vendor/a".into()]).unwrap();
            std::fs::write("vendor/a/file", "changed after planning").unwrap();
            let head = git(&["rev-parse", "HEAD"]);
            assert_eq!(execution.run(), Err(Fail::Hard));
            assert_eq!(git(&["rev-parse", "HEAD"]), head);
        });
    }

    #[test]
    fn paused_recursive_rebase_replays_own_commit_only_after_folding() {
        with_repository(|| {
            let mut context = ExecutionContext::new();
            nested_updates(&mut context);
            std::fs::write("own-file", "my own change").unwrap();
            git(&["add", "own-file"]);
            git(&["commit", "-qm", "Own change"]);
            let own = git(&["rev-parse", "HEAD"]);
            let mut execution = start(
                &mut context,
                &["--recursive".into(), "--rebase".into(), "vendor/a".into()],
            )
            .unwrap();
            execution
                .run_until(|event| matches!(event, ExecutionEvent::BeforeFold { .. }))
                .unwrap();
            let before_fold = git(&["rev-parse", "HEAD"]);
            let outcome = execution
                .run_until(|event| matches!(event, ExecutionEvent::AfterFold { .. }))
                .unwrap();
            let folded = git(&["rev-parse", "HEAD"]);
            assert_eq!(
                outcome,
                ExecutionOutcome::Paused(ExecutionEvent::AfterFold {
                    roots: vec!["vendor/a".into()],
                    head_before: before_fold,
                    head_after: folded.clone()
                })
            );
            assert_eq!(git(&["rev-parse", "main"]), own);
            assert_eq!(git(&["rev-parse", "--abbrev-ref", "HEAD"]), "HEAD");
            assert!(!std::path::Path::new("own-file").exists());
            assert_eq!(execution.run(), Ok(0));
            assert_eq!(git(&["branch", "--show-current"]), "main");
            assert_eq!(git(&["rev-parse", "HEAD^"]), folded);
            assert_eq!(
                std::fs::read_to_string("own-file").unwrap(),
                "my own change"
            );
            assert_eq!(git(&["log", "-1", "--format=%s"]), "Own change");
        });
    }

    #[test]
    fn paused_recursive_rebase_rejects_a_moved_original_branch_before_replay() {
        with_repository(|| {
            let mut context = ExecutionContext::new();
            nested_updates(&mut context);
            std::fs::write("own-file", "my own change").unwrap();
            git(&["add", "own-file"]);
            git(&["commit", "-qm", "Own change"]);
            let own = git(&["rev-parse", "HEAD"]);
            let mut execution = start(
                &mut context,
                &["--recursive".into(), "--rebase".into(), "vendor/a".into()],
            )
            .unwrap();
            assert!(matches!(
                execution
                    .run_until(|event| matches!(event, ExecutionEvent::AfterFold { .. }))
                    .unwrap(),
                ExecutionOutcome::Paused(ExecutionEvent::AfterFold { .. })
            ));
            let folded = git(&["rev-parse", "HEAD"]);
            let moved = git(&["rev-parse", &format!("{own}^")]);
            git(&["update-ref", "refs/heads/main", &moved, &own]);

            assert_eq!(execution.run(), Err(Fail::Hard));
            assert_eq!(execution.run(), Err(Fail::Hard));
            assert_eq!(git(&["rev-parse", "HEAD"]), folded);
            assert_eq!(git(&["rev-parse", "main"]), moved);
            assert_eq!(
                git(&["symbolic-ref", "SPLICE_PULL_BRANCH"]),
                "refs/heads/main"
            );
        });
    }

    #[test]
    fn pull_continuation_rejects_tracked_file_index_and_marker_changes() {
        enum Change {
            TrackedFile,
            Index,
            FoldStart,
            RebaseBranch,
        }
        for change in [
            Change::TrackedFile,
            Change::Index,
            Change::FoldStart,
            Change::RebaseBranch,
        ] {
            with_repository(|| {
                let mut context = ExecutionContext::new();
                nested_updates(&mut context);
                let mut execution =
                    start(&mut context, &["--recursive".into(), "vendor/a".into()]).unwrap();
                assert!(matches!(
                    execution
                        .run_until(|event| matches!(event, ExecutionEvent::BeforeFold { .. }))
                        .unwrap(),
                    ExecutionOutcome::Paused(ExecutionEvent::BeforeFold { .. })
                ));
                let head = git(&["rev-parse", "HEAD"]);
                match change {
                    Change::TrackedFile => {
                        std::fs::write("vendor/a/file", "edited while paused").unwrap()
                    }
                    Change::Index => {
                        std::fs::write("vendor/a/file", "staged while paused").unwrap();
                        git(&["add", "vendor/a/file"]);
                        std::fs::write("vendor/a/file", "new parent\n").unwrap();
                    }
                    Change::FoldStart => {
                        std::fs::write(git(&["rev-parse", "--git-path", START]), "changed").unwrap()
                    }
                    Change::RebaseBranch => std::fs::write(
                        git(&["rev-parse", "--git-path", "SPLICE_PULL_BRANCH"]),
                        "changed",
                    )
                    .unwrap(),
                }
                assert_eq!(execution.run(), Err(Fail::Hard));
                assert_eq!(execution.run(), Err(Fail::Hard));
                assert_eq!(git(&["rev-parse", "HEAD"]), head);
            });
        }
    }

    #[test]
    fn named_pull_checkpoints_pause_before_folding_and_continue_without_refetching() {
        with_repository(|| {
            let fixture = NestedFixture {
                parent: SpliceFixture {
                    path: "vendor/a",
                    upstream: "parent",
                    file: FileVersions {
                        before: "parent v1",
                        after: "parent v2",
                    },
                },
                child: SpliceFixture {
                    path: "vendor/a/b",
                    upstream: "child",
                    file: FileVersions {
                        before: "child v1",
                        after: "child v2",
                    },
                },
            };
            let mut context = ExecutionContext::new();
            let updates = setup_nested_updates(&mut context, &fixture);
            let initial = git(&["rev-parse", "HEAD"]);
            let mut names = vec![
                ("S", initial.as_str()),
                ("A0", updates.parent_before.as_str()),
                ("B0", updates.child_before.as_str()),
                ("A1", updates.parent.as_str()),
                ("B1", updates.child.as_str()),
            ];
            assert_pull_diagram(
                "Initial fixture",
                &fixture,
                &updates,
                &initial,
                &names,
                r#"main -> S
history: S
fetched: a -> A0, a/b -> B0
recorded: a -> A0, a/b -> B0
files: a = "parent v1", a/b = "child v1"
fold start -> -"#,
            );
            let mut execution =
                start(&mut context, &["--recursive".into(), "vendor/a".into()]).unwrap();
            let paused = execution
                .run_until(|event| matches!(event, ExecutionEvent::AfterFetch { .. }))
                .unwrap();
            assert!(matches!(
                paused,
                ExecutionOutcome::Paused(ExecutionEvent::AfterFetch { .. })
            ));
            assert_pull_diagram(
                "Paused: initial downloads complete",
                &fixture,
                &updates,
                &initial,
                &names,
                r#"main -> S
history: S
fetched: a -> A1, a/b -> B1
recorded: a -> A0, a/b -> B0
files: a = "parent v1", a/b = "child v1"
fold start -> -"#,
            );
            std::fs::rename("parent", "parent.offline").unwrap();
            std::fs::rename("child", "child.offline").unwrap();
            let paused = execution
                .run_until(|event| matches!(event, ExecutionEvent::AfterMerge { .. }))
                .unwrap();
            let parent_head = git(&["rev-parse", "HEAD"]);
            assert_eq!(
                paused,
                ExecutionOutcome::Paused(ExecutionEvent::AfterMerge {
                    path: "vendor/a".into(),
                    head_before: initial.clone(),
                    head_after: parent_head.clone()
                })
            );
            names.push(("P", &parent_head));
            assert_pull_diagram(
                "Paused: parent merged",
                &fixture,
                &updates,
                &initial,
                &names,
                r#"main -> P
history: S -- P
fetched: a -> A1, a/b -> B1
recorded: a -> A1, a/b -> B0
files: a = "parent v2", a/b = "child v1"
fold start -> S"#,
            );
            let paused = execution
                .run_until(|event| matches!(event, ExecutionEvent::AfterMerge { .. }))
                .unwrap();
            let child_head = git(&["rev-parse", "HEAD"]);
            assert_eq!(
                paused,
                ExecutionOutcome::Paused(ExecutionEvent::AfterMerge {
                    path: "vendor/a/b".into(),
                    head_before: parent_head.clone(),
                    head_after: child_head.clone()
                })
            );
            names.push(("C", &child_head));
            assert_pull_diagram(
                "Paused: child merged",
                &fixture,
                &updates,
                &initial,
                &names,
                r#"main -> C
history: S -- P -- C
fetched: a -> A1, a/b -> B1
recorded: a -> A1, a/b -> B1
files: a = "parent v2", a/b = "child v2"
fold start -> S"#,
            );
            assert_eq!(
                execution
                    .run_until(|event| matches!(event, ExecutionEvent::BeforeFold { .. }))
                    .unwrap(),
                ExecutionOutcome::Paused(ExecutionEvent::BeforeFold {
                    roots: vec!["vendor/a".into()],
                    head: child_head.clone()
                })
            );
            assert_pull_diagram(
                "Paused: BEFORE folding",
                &fixture,
                &updates,
                &initial,
                &names,
                r#"main -> C
history: S -- P -- C
fetched: a -> A1, a/b -> B1
recorded: a -> A1, a/b -> B1
files: a = "parent v2", a/b = "child v2"
fold start -> S"#,
            );
            let tree = git(&["rev-parse", "HEAD^{tree}"]);
            let paused = execution
                .run_until(|event| matches!(event, ExecutionEvent::AfterFold { .. }))
                .unwrap();
            let folded = git(&["rev-parse", "HEAD"]);
            assert_eq!(
                paused,
                ExecutionOutcome::Paused(ExecutionEvent::AfterFold {
                    roots: vec!["vendor/a".into()],
                    head_before: child_head.clone(),
                    head_after: folded.clone()
                })
            );
            names.push(("F", &folded));
            assert_eq!(git(&["rev-parse", "HEAD^{tree}"]), tree);
            assert_pull_diagram(
                "Paused: AFTER folding, before cleanup",
                &fixture,
                &updates,
                &initial,
                &names,
                r#"main -> F
history: S -- F
fetched: a -> A1, a/b -> B1
recorded: a -> A1, a/b -> B1
files: a = "parent v2", a/b = "child v2"
fold start -> S"#,
            );
            assert_eq!(execution.run().unwrap(), 0);
            assert_pull_diagram(
                "Complete: start marker cleared",
                &fixture,
                &updates,
                &initial,
                &names,
                r#"main -> F
history: S -- F
fetched: a -> A1, a/b -> B1
recorded: a -> A1, a/b -> B1
files: a = "parent v2", a/b = "child v2"
fold start -> -"#,
            );
            assert_eq!(
                execution.run_until(|_| true).unwrap(),
                ExecutionOutcome::Complete(0)
            );
            assert_eq!(git(&["rev-parse", "HEAD"]), folded);
        });
    }

    #[test]
    fn observer_and_exec_hook_see_fetch_merge_and_fold_boundaries() {
        #[derive(Debug)]
        struct Observation {
            event: ExecutionEvent,
            head: String,
            commits: usize,
            tree: String,
        }

        with_repository(|| {
            use crate::execution::FetchedUpstream;
            use ExecutionEvent::*;

            let mut context = ExecutionContext::new();
            nested_updates(&mut context);
            let root = std::env::current_dir().unwrap();
            let start = git(&["rev-parse", "HEAD"]);
            let observed_start = start.clone();
            let observations = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
            let recorded = observations.clone();
            context.set_observer(move |event| {
                recorded.lock().unwrap().push(Observation {
                    event: event.clone(),
                    head: git(&["rev-parse", "HEAD"]),
                    commits: git(&["rev-list", "--count", &format!("{observed_start}..HEAD")])
                        .parse()
                        .unwrap(),
                    tree: git(&["rev-parse", "HEAD^{tree}"]),
                });
            });
            assert_eq!(
                run(
                    &mut context,
                    &[
                        "--recursive".into(),
                        "--exec".into(),
                        r#"test -z "$GIT_SPLICE_COMMIT" && printf '%s:%s\n' "$GIT_SPLICE_EVENT" "$GIT_SPLICE_PATH" >> hook-events"#.into(),
                        "vendor/a".into(),
                    ],
                )
                .unwrap(),
                0
            );
            assert_eq!(
                std::fs::read_to_string("hook-events").unwrap(),
                "after-fetch:\nafter-merge:vendor/a\nafter-merge:vendor/a/b\nbefore-fold:\nafter-fold:\n"
            );
            let observed = observations.lock().unwrap();
            assert_eq!(observed.len(), 5, "{observed:#?}");
            let parent_head = observed[1].head.clone();
            let child_head = observed[2].head.clone();
            let folded_head = git(&["rev-parse", "HEAD"]);
            let fetched = vec![
                FetchedUpstream {
                    path: "vendor/a".into(),
                    upstream: "origin".into(),
                    url: root.join("parent").to_string_lossy().into_owned(),
                    failed: false,
                },
                FetchedUpstream {
                    path: "vendor/a/b".into(),
                    upstream: "origin".into(),
                    url: root.join("child").to_string_lossy().into_owned(),
                    failed: false,
                },
            ];
            assert_eq!(
                observed
                    .iter()
                    .map(|row| row.event.clone())
                    .collect::<Vec<_>>(),
                vec![
                    AfterFetch {
                        fetched: fetched.clone()
                    },
                    AfterMerge {
                        path: "vendor/a".into(),
                        head_before: start.clone(),
                        head_after: parent_head.clone(),
                    },
                    AfterMerge {
                        path: "vendor/a/b".into(),
                        head_before: parent_head.clone(),
                        head_after: child_head.clone(),
                    },
                    BeforeFold {
                        roots: vec!["vendor/a".into()],
                        head: child_head.clone()
                    },
                    AfterFold {
                        roots: vec!["vendor/a".into()],
                        head_before: child_head.clone(),
                        head_after: folded_head.clone(),
                    },
                ],
                "observed checkpoints:\n{observed:#?}"
            );
            assert_eq!(
                observed
                    .iter()
                    .map(|row| row.head.as_str())
                    .collect::<Vec<_>>(),
                [
                    start.as_str(),
                    parent_head.as_str(),
                    child_head.as_str(),
                    child_head.as_str(),
                    folded_head.as_str(),
                ]
            );
            assert_eq!(
                observed.iter().map(|row| row.commits).collect::<Vec<_>>(),
                [0, 1, 2, 2, 1]
            );
            assert_eq!(observed[3].tree, observed[4].tree);
            drop(observed);
            observations.lock().unwrap().clear();
            assert_eq!(
                run(&mut context, &["--recursive".into(), "vendor/a".into()]).unwrap(),
                0
            );
            let observed = observations.lock().unwrap();
            assert_eq!(
                observed
                    .iter()
                    .map(|row| row.event.clone())
                    .collect::<Vec<_>>(),
                vec![
                    AfterFetch { fetched },
                    BeforeFold {
                        roots: vec!["vendor/a".into()],
                        head: folded_head.clone()
                    },
                    AfterFold {
                        roots: vec!["vendor/a".into()],
                        head_before: folded_head.clone(),
                        head_after: folded_head
                    },
                ],
                "observed checkpoints:\n{observed:#?}"
            );
        });
    }

    #[test]
    fn recursive_pull_retains_downloads_then_exposes_unfolded_merges_before_finalization() {
        with_repository(|| {
            let mut context = ExecutionContext::new();
            let updates = nested_updates(&mut context);
            let before = git(&["rev-parse", "HEAD"]);
            let (mut repo, mut progress) = progress(&mut context);
            progress.advance(&mut repo).unwrap();
            assert!(matches!(progress.phase, PullPhase::Fetched(_)));
            assert_eq!(git(&["rev-parse", "HEAD"]), before);
            assert_eq!(
                git(&["rev-parse", &repo.splice_ref("vendor/a", "main")]),
                updates.parent
            );
            assert_eq!(
                git(&["rev-parse", &repo.splice_ref("vendor/a/b", "main")]),
                updates.child
            );
            assert_eq!(
                std::fs::read_to_string("vendor/a/file").unwrap(),
                "old parent\n"
            );
            assert_eq!(
                std::fs::read_to_string("vendor/a/b/file").unwrap(),
                "old child\n"
            );
            std::fs::rename("parent", "parent.offline").unwrap();
            std::fs::rename("child", "child.offline").unwrap();
            while !matches!(progress.phase, PullPhase::Finalize) {
                progress.advance(&mut repo).unwrap();
            }
            assert_eq!(
                git(&["rev-list", "--count", &format!("{before}..HEAD")]),
                "2"
            );
            assert_eq!(git(&["rev-parse", START]), before);
            assert_eq!(splice_config("vendor/a", "commit", "HEAD"), updates.parent);
            assert_eq!(splice_config("vendor/a/b", "commit", "HEAD"), updates.child);
            let unfolded = git(&["rev-parse", "HEAD"]);
            let tree = git(&["rev-parse", "HEAD^{tree}"]);
            while !progress.done() {
                progress.advance(&mut repo).unwrap();
            }
            assert!(progress.done());
            assert_eq!(progress.finish().unwrap(), 0);
            assert_eq!(
                git(&["rev-list", "--count", &format!("{before}..HEAD")]),
                "1"
            );
            assert_ne!(git(&["rev-parse", "HEAD"]), unfolded);
            assert_eq!(git(&["rev-parse", "HEAD^{tree}"]), tree);
            assert!(!std::path::Path::new(&git(&["rev-parse", "--git-path", START])).exists());
            let folded = git(&["rev-parse", "HEAD"]);
            progress.advance(&mut repo).unwrap();
            assert_eq!(git(&["rev-parse", "HEAD"]), folded);
        });
    }

    #[test]
    fn partial_fetch_failure_still_folds_successful_work_and_cleans_up_before_reporting_failure() {
        with_repository(|| {
            let mut context = ExecutionContext::new();
            nested_updates(&mut context);
            let root = std::env::current_dir().unwrap();
            crate::clone::run(
                &mut context,
                &[
                    root.join("parent").to_string_lossy().into_owned(),
                    "vendor/z".into(),
                ],
            )
            .unwrap();
            git(&[
                "config",
                "--file",
                "vendor/z/.splice",
                "upstream.origin.url",
                &root.join("missing").to_string_lossy(),
            ]);
            git(&["add", "vendor/z/.splice"]);
            git(&["commit", "-qm", "unavailable independent upstream"]);
            let before = git(&["rev-parse", "HEAD"]);
            let args = parse_args(USAGE, "", &["--all".into()]).unwrap();
            let mut repo = Repo::new(&mut context, args);
            apply_merge_options(&mut repo).unwrap();
            repo.open().unwrap();
            let mut progress = PullProgress::new(&mut repo).unwrap();
            while !matches!(progress.phase, PullPhase::Finalize) {
                progress.advance(&mut repo).unwrap();
            }
            assert!(progress.fetch_failures.contains(&"vendor/z".into()));
            assert_eq!(progress.status, 0);
            assert_eq!(
                git(&["rev-list", "--count", &format!("{before}..HEAD")]),
                "2"
            );
            while !progress.done() {
                progress.advance(&mut repo).unwrap();
            }
            assert_eq!(progress.finish().unwrap(), 1);
            assert_eq!(
                git(&["rev-list", "--count", &format!("{before}..HEAD")]),
                "1"
            );
            assert!(!std::path::Path::new(&git(&["rev-parse", "--git-path", START])).exists());
        });
    }

    #[test]
    fn drops_the_conflicts_git_lists_after_a_conflict() {
        let message = "splice: pull c\n\n# Conflicts:\n#\tc/file.txt\n#\tc/other.txt\n";
        assert_eq!(without_conflicts(message), "splice: pull c");
    }

    #[test]
    fn keeps_other_lines_starting_with_a_hash() {
        let message = "#123: pull c\n\n# Changes\n- c2";
        assert_eq!(without_conflicts(message), message);
    }

    #[test]
    fn keeps_a_conflicts_heading_without_files_listed() {
        let message = "splice: pull c\n\n# Conflicts:\nnone, c2 merged cleanly";
        assert_eq!(without_conflicts(message), message);
    }
}
