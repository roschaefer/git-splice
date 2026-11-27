//! git splice fetch.

use crate::args::parse_args;
use crate::context::ExecutionContext;
use crate::execution::{ExecutionEvent, FetchedUpstream};
use crate::repo::*;
use crate::util::*;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

pub const USAGE: &str = include_str!("usage/fetch.txt");

/// Fetches every branch of upstream <url> into <prefix>*, pruning those that
/// are gone, with a reflog for each, as Git keeps for refs/remotes/: merge finds
/// a rewritten branch's fork point in it. The rebuild starts at a splice's
/// synced commit; any commit given that no branch upstream has any more is
/// fetched by id. Returns whether it worked, and what git printed.
pub fn fetch_upstream(url: &str, prefix: &str, commits: &[String]) -> (bool, String) {
    let refspec = format!("+refs/heads/*:{prefix}*");
    let (ok, output) = git_merged_output(&[
        "-c",
        "core.logAllRefUpdates=always",
        "fetch",
        "--quiet",
        "--no-recurse-submodules",
        "--no-tags",
        "--no-write-fetch-head",
        "--prune",
        "--",
        url,
        &refspec,
    ]);
    if !ok {
        return (false, output);
    }
    for commit in commits {
        // A splice made by init has no synced commit until its first pull.
        if !commit.is_empty() && !commit_here(commit) {
            fetch_by_id(url, commit);
        }
    }
    (true, output)
}

/// Whether GIT_LFS_SKIP_SMUDGE asks Git LFS to check files out as pointers:
/// their content isn't needed here then.
fn lfs_skipped() -> bool {
    std::env::var("GIT_LFS_SKIP_SMUDGE").is_ok_and(|value| lfs_true(&value))
}

/// Whether Git LFS reads <value> as true.
fn lfs_true(value: &str) -> bool {
    matches!(
        value.to_ascii_lowercase().as_str(),
        "1" | "true" | "yes" | "on" | "t"
    )
}

/// Whether a .gitattributes in <commit> stores files in Git LFS.
fn uses_lfs(commit: &str) -> bool {
    git(&[
        "grep",
        "--quiet",
        "--fixed-strings",
        "filter=lfs",
        commit,
        "--",
        ":(glob)**/.gitattributes",
    ])
    .q()
    .ok()
}

/// Downloads the Git LFS content of <commit>'s files from upstream <url>'s LFS
/// server into this repository's LFS store. A checkout of <commit> looks for
/// it there before it asks the monorepo's own LFS server, which doesn't have it
/// yet; the monorepo's next push uploads it there. Content that's here already
/// isn't downloaded again. On failure, returns what to say.
pub fn download_lfs(url: &str, commit: &str) -> Result<(), String> {
    if commit.is_empty() || lfs_skipped() || !uses_lfs(commit) {
        return Ok(());
    }
    // lfs.fetchinclude and lfs.fetchexclude name the monorepo's paths, not the
    // upstream's.
    let (ok, output) = git_merged_output(&[
        "lfs",
        "fetch",
        "--include=",
        "--exclude=",
        "--",
        url,
        commit,
    ]);
    if ok {
        return Ok(());
    }
    if !git(&["lfs", "version"]).q().ok() {
        return Err(format!(
            "{} stores files in Git LFS, which isn't installed here",
            short(commit)
        ));
    }
    Err(output)
}

pub fn fetch_by_id(url: &str, commit: &str) -> bool {
    git(&[
        "fetch",
        "--quiet",
        "--no-recurse-submodules",
        "--no-tags",
        "--no-write-fetch-head",
        "--",
        url,
        commit,
    ])
    .q()
    .ok()
}

/// Fetches tag <tag> of upstream <url> into <prefix>tags/<tag>, if upstream has
/// it. Git doesn't move a fetched tag that moved upstream, and neither does
/// this: it keeps the commit the tag named, and returns (old, new) then.
fn fetch_tag(url: &str, prefix: &str, tag: &str) -> Option<(String, String)> {
    let reference = format!("{prefix}tags/{tag}");
    let verify = |reference: &str| git(&["rev-parse", "--verify", "--quiet", reference]).out();
    let old = verify(&reference);
    let refspec = format!("+refs/tags/{tag}:{reference}");
    let fetched = git(&[
        "-c",
        "core.logAllRefUpdates=always",
        "fetch",
        "--quiet",
        "--no-recurse-submodules",
        "--no-tags",
        "--no-write-fetch-head",
        "--",
        url,
        &refspec,
    ])
    .q()
    .ok();
    if !fetched {
        return None;
    }
    let new = verify(&reference)?;
    let old = old?;
    if new == old {
        return None;
    }
    git(&["update-ref", &reference, &old]).ok();
    Some((old, new))
}

/// What a fetch needs to know of one upstream of one splice: all read before
/// the fetches start in parallel.
struct Member {
    index: usize,
    path: String,
    label: String,
    failed_label: String,
    upstream_branch: String,
    target_ref: String,
    old_sha: Option<String>,
    tag: String,
    /// A default-pin that names a commit.
    pinned_commit: String,
}

/// What to print for an entry of a fetch.
#[derive(Default, Clone)]
struct Report {
    out: String,
    err: String,
    failed: bool,
}

/// Fetches an upstream the given splices share, and reports for each whether
/// the branch it syncs with moved.
fn fetch_shared_upstream(
    key: &str,
    url: &str,
    commits: &[String],
    members: &[Member],
) -> Vec<(usize, Report)> {
    let mut reports = Vec::new();
    let (ok, output) = fetch_upstream(url, &format!("refs/splices/{key}/heads/"), commits);
    if !ok {
        for member in members {
            let mut err = String::new();
            if !output.is_empty() {
                err.push_str(&output);
                err.push('\n');
            }
            err.push_str(&format!("!!   {}", member.failed_label));
            reports.push((
                member.index,
                Report {
                    out: String::new(),
                    err,
                    failed: true,
                },
            ));
        }
        return reports;
    }
    let prefix = format!("refs/splices/{key}/");
    let mut moved_tags: Vec<(String, Option<(String, String)>)> = Vec::new();
    for member in members {
        if !member.tag.is_empty() && !moved_tags.iter().any(|(tag, _)| *tag == member.tag) {
            let moved = fetch_tag(url, &prefix, &member.tag);
            moved_tags.push((member.tag.clone(), moved));
        }
    }
    let mut downloaded: Vec<(String, Result<(), String>)> = Vec::new();
    for (i, member) in members.iter().enumerate() {
        let new_sha = git(&["rev-parse", "--verify", "--quiet", &member.target_ref]).out();
        // What a merge would check out: the branch, or else the pin.
        let target = match &new_sha {
            Some(sha) => sha.clone(),
            None if !member.tag.is_empty() => {
                commit_of(&format!("{prefix}tags/{}", member.tag)).unwrap_or_default()
            }
            None => member.pinned_commit.clone(),
        };
        let download = match downloaded.iter().find(|(commit, _)| *commit == target) {
            Some((_, result)) => result.clone(),
            None => {
                let result = download_lfs(url, &target);
                downloaded.push((target.clone(), result.clone()));
                result
            }
        };
        if let Err(output) = download {
            reports.push((
                member.index,
                Report {
                    out: String::new(),
                    err: format!("{output}\n!!   {}", member.failed_label),
                    failed: true,
                },
            ));
            continue;
        }
        let out = match (&member.old_sha, &new_sha) {
            (Some(old), Some(new)) if old != new => format!(
                "ok   {} ({} moved {}..{})",
                member.label,
                member.upstream_branch,
                short(old),
                short(new)
            ),
            _ => format!("ok   {}", member.label),
        };
        let mut err_lines = Vec::new();
        // What git printed on success, e.g. an SSH warning, shown once.
        if i == 0 && !output.is_empty() {
            err_lines.push(output.clone());
        }
        let moved = moved_tags
            .iter()
            .find(|(tag, _)| *tag == member.tag)
            .and_then(|(_, moved)| moved.as_ref());
        if let Some((old, new)) = moved {
            err_lines.push(format!(
                "??   {}: the tag '{}' moved upstream, from {} to {} -- kept {}; to take the new one: git update-ref refs/splices/{key}/tags/{} {new}",
                member.path,
                member.tag,
                short(old),
                short(new),
                short(old),
                member.tag
            ));
        }
        reports.push((
            member.index,
            Report {
                out,
                err: err_lines.join("\n"),
                failed: false,
            },
        ));
    }
    reports
}

/// Paths whose fetch failed.
pub type FetchFailures = Vec<String>;

impl Repo<'_> {
    /// Fetches the upstreams of every given (distinct) entry in parallel, each
    /// (path, name) of an upstream of a splice, and each upstream once: splices
    /// with the same URL share their fetched refs, and two fetches into the
    /// same refs would fail on each other's locks. Prints what there is to say
    /// about each entry, in their order, and returns the paths that failed.
    pub fn fetch_all(&mut self, branch: &str, entries: &[(String, String)]) -> Res<FetchFailures> {
        let (failures, event) = self
            .prepare_fetch(branch, entries)?
            .download()
            .finish(self)?;
        self.context.emit(event);
        Ok(failures)
    }

    pub(crate) fn prepare_fetch(
        &mut self,
        branch: &str,
        entries: &[(String, String)],
    ) -> Res<FetchPlan> {
        // Before the fetches start in parallel, which would race to record keys.
        let mut groups: Vec<(String, String, Vec<usize>)> = Vec::new();
        let mut new_keys = Vec::new();
        for (i, (path, name)) in entries.iter().enumerate() {
            self.require_upstream_list(path)?;
            let url = self.url_of(path, name);
            let recorded = !self.upstream_key(&url)?.is_empty();
            let key = self.create_upstream_key(&url)?;
            if !recorded {
                new_keys.push(key.clone());
            }
            match groups.iter_mut().find(|(k, _, _)| *k == key) {
                Some((_, _, indexes)) => indexes.push(i),
                None => groups.push((key, url, vec![i])),
            }
        }
        // Splices whose upstream in use just got its key.
        for path in self.urls.keys().cloned().collect::<Vec<_>>() {
            if !self.url_in_use(&path).is_empty() && self.key_of(&path).is_empty() {
                let url = self.url_in_use(&path);
                let key = self.upstream_key(&url)?;
                self.keys.insert(path, key);
            }
        }

        let mut jobs = Vec::new();
        for (key, url, indexes) in groups {
            let mut commits = Vec::new();
            let mut members = Vec::new();
            for index in indexes {
                let (path, name) = &entries[index];
                let from = if self.several_upstreams(path) {
                    format!(" from {name}")
                } else {
                    String::new()
                };
                // Empty if the upstreams of the splice above disagree on it,
                // and none is its default: the commands that need it refuse
                // then.
                let upstream_branch =
                    quietly(|| self.upstream_branch_for(path, branch, Some(name)))
                        .unwrap_or_default();
                // Only a default-pin fetches a tag or a commit. Every branch
                // fetches it: a feature branch compares with it when upstream
                // has no branch like it.
                let pin = self.upstream_setting(path, name, "default-pin");
                let (tag, pinned_commit) = if is_commit_id(&pin) {
                    commits.push(pin.clone());
                    (String::new(), pin.clone())
                } else {
                    (pin.clone(), String::new())
                };
                // A splice pinned on this branch has no branch that could move.
                let follows_branch = pin.is_empty()
                    || self.branch_arg_applies(path)
                    || (*name == self.name_of(path) && self.named_branch(path, branch).is_some())
                    || branch != self.monorepo_default_branch();
                let target_ref = if follows_branch {
                    format!("refs/splices/{key}/heads/{upstream_branch}")
                } else {
                    String::new()
                };
                let old_sha = git(&["rev-parse", "--verify", "--quiet", &target_ref]).out();
                commits.push(splice_config(path, "commit", &self.state_rev));
                members.push(Member {
                    index,
                    path: path.clone(),
                    label: format!("{path} fetched{from}"),
                    failed_label: format!("{path} fetch{from} failed"),
                    upstream_branch,
                    target_ref,
                    old_sha,
                    tag,
                    pinned_commit,
                });
            }
            jobs.push(FetchJob {
                key,
                url,
                commits,
                members,
            });
        }

        Ok(FetchPlan {
            entries: entries.to_vec(),
            jobs,
            new_keys,
        })
    }

    /// An entry for fetch_all for each upstream of each splice.
    pub fn every_upstream_entry(&mut self, paths: &[String]) -> Res<Vec<(String, String)>> {
        let mut entries = Vec::new();
        for path in paths {
            self.require_upstream_list(path)?;
            for name in &self.upstream_lists[path] {
                entries.push((path.clone(), name.clone()));
            }
        }
        Ok(entries)
    }

    /// An entry for fetch_all for the upstream each splice uses.
    pub fn used_upstream_entry(&self, paths: &[String]) -> Vec<(String, String)> {
        paths
            .iter()
            .map(|path| (path.clone(), self.name_of(path)))
            .collect()
    }
}

/// How many upstreams fetch at once: under OpenSSH's default MaxStartups of
/// 10, beyond which sshd drops new connections at random.
const MAX_CONCURRENT_FETCHES: usize = 8;

/// Reports every member of a fetch that panicked as failed, so that it isn't
/// taken for fetched.
fn crashed(members: &[Member]) -> Vec<(usize, Report)> {
    members
        .iter()
        .map(|member| {
            (
                member.index,
                Report {
                    out: String::new(),
                    err: format!("!!   {}", member.failed_label),
                    failed: true,
                },
            )
        })
        .collect()
}

struct FetchJob {
    key: String,
    url: String,
    commits: Vec<String>,
    members: Vec<Member>,
}

pub(crate) struct FetchPlan {
    entries: Vec<(String, String)>,
    jobs: Vec<FetchJob>,
    new_keys: Vec<String>,
}

pub(crate) struct FetchResults {
    plan: FetchPlan,
    reports: Vec<Report>,
    event: ExecutionEvent,
}

impl FetchPlan {
    pub(crate) fn download(self) -> FetchResults {
        let mut reports = vec![Report::default(); self.entries.len()];
        let next = AtomicUsize::new(0);
        let done = Mutex::new(Vec::new());
        std::thread::scope(|scope| {
            for _ in 0..self.jobs.len().min(MAX_CONCURRENT_FETCHES) {
                scope.spawn(|| {
                    while let Some(job) = self.jobs.get(next.fetch_add(1, Ordering::Relaxed)) {
                        let fetched = std::panic::catch_unwind(|| {
                            fetch_shared_upstream(&job.key, &job.url, &job.commits, &job.members)
                        })
                        .unwrap_or_else(|_| crashed(&job.members));
                        done.lock()
                            .unwrap_or_else(|e| e.into_inner())
                            .extend(fetched);
                    }
                });
            }
        });
        for (index, report) in done.into_inner().unwrap_or_else(|e| e.into_inner()) {
            reports[index] = report;
        }

        let mut fetched = Vec::new();
        for job in &self.jobs {
            for member in &job.members {
                let (path, upstream) = &self.entries[member.index];
                fetched.push((
                    member.index,
                    FetchedUpstream {
                        path: path.clone(),
                        upstream: upstream.clone(),
                        url: job.url.clone(),
                        failed: reports[member.index].failed,
                    },
                ));
            }
        }
        fetched.sort_by_key(|(index, _)| *index);

        FetchResults {
            plan: self,
            reports,
            event: ExecutionEvent::AfterFetch {
                fetched: fetched.into_iter().map(|(_, entry)| entry).collect(),
            },
        }
    }
}

impl FetchResults {
    /// Prints the reports and forgets the keys of new upstreams that all
    /// failed. The event follows, so it describes a finished fetch.
    pub(crate) fn finish(self, repo: &mut Repo) -> Res<(FetchFailures, ExecutionEvent)> {
        let mut failures = Vec::new();
        for ((path, _), report) in self.plan.entries.iter().zip(&self.reports) {
            if !report.out.is_empty() {
                say(&report.out);
            }
            if !report.err.is_empty() {
                eprint_text(&format!("{}\n", report.err));
            }
            if report.failed && !failures.contains(path) {
                failures.push(path.clone());
            }
        }
        for job in &self.plan.jobs {
            if self.plan.new_keys.contains(&job.key)
                && job.members.iter().all(|m| self.reports[m.index].failed)
            {
                repo.forget_upstream_key(&job.key)?;
            }
        }
        Ok((failures, self.event))
    }
}

pub fn run(context: &mut ExecutionContext, argv: &[String]) -> Res<i32> {
    let args = parse_args(USAGE, "--upstream --branch --track --no-track", argv)?;
    args.require_branch_for_track()?;
    let mut repo = Repo::new(context, args);
    repo.open()?;
    repo.select_paths(Kind::Overview, "fetch")?;
    let branch = current_branch()?;
    let selected = repo.selected.clone();
    let track = repo.args.has_flag("--track");
    let no_track = repo.args.has_flag("--no-track");
    let upstream = repo.args.upstream.clone();

    // Tracking is per upstream in use, so only that one is fetched.
    let entries = if !upstream.is_empty() || track || no_track {
        repo.use_upstreams(&upstream, &selected)?;
        repo.used_upstream_entry(&selected)
    } else {
        repo.every_upstream_entry(&selected)?
    };
    let fetch_failures = repo.fetch_all(&branch, &entries)?;
    for path in &fetch_failures {
        repo.context.leave_out(path);
    }

    for path in &selected {
        if fetch_failures.contains(path) {
            continue;
        }
        if track {
            let wanted = repo.args.branch.clone();
            let reference = format!("refs/splices/{}/heads/{wanted}", repo.key_of(path));
            if git(&["rev-parse", "--verify", "--quiet", &reference])
                .q()
                .ok()
            {
                match repo.track_branch(path, &branch, &wanted) {
                    Err(Fail::Hard) => return Err(Fail::Hard),
                    Err(_) => repo.context.leave_out(path),
                    Ok(()) => {}
                }
            } else {
                log_err(format!(
                    "{path}: upstream has no '{wanted}' branch to track"
                ));
                repo.context.leave_out(path);
            }
        } else if no_track {
            match repo.untrack_branch(path, &branch) {
                Err(Fail::Hard) => return Err(Fail::Hard),
                Err(_) => repo.context.leave_out(path),
                Ok(()) => {}
            }
        }
    }
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::test_repo::{git, with_repository};

    #[test]
    fn reads_git_lfs_booleans_as_git_lfs_does() {
        for (value, expected) in [
            ("1", true),
            ("true", true),
            ("TRUE", true),
            ("yes", true),
            ("on", true),
            ("t", true),
            ("T", true),
            ("y", false),
            ("2", false),
            ("false", false),
            ("0", false),
            ("f", false),
            ("no", false),
            ("off", false),
            ("", false),
        ] {
            assert_eq!(lfs_true(value), expected, "{value:?}");
        }
    }

    fn upstream() -> String {
        git(&["config", "user.name", "Test"]);
        git(&["config", "user.email", "test@example.com"]);
        git(&["commit", "--allow-empty", "-qm", "initial"]);
        git(&["init", "-q", "--initial-branch=main", "upstream"]);
        std::fs::write("upstream/file", "old\n").unwrap();
        git(&["-C", "upstream", "add", "."]);
        git(&["-C", "upstream", "commit", "-qm", "initial upstream"]);
        std::env::current_dir()
            .unwrap()
            .join("upstream")
            .to_string_lossy()
            .into_owned()
    }

    fn repo(context: &mut ExecutionContext) -> Repo<'_> {
        let mut repo = Repo::new(context, Default::default());
        repo.open().unwrap();
        repo.select_paths(Kind::Overview, "fetch").unwrap();
        repo
    }

    #[test]
    fn a_fetch_that_panicked_fails_every_splice_of_its_upstream() {
        let member = |index: usize, path: &str| Member {
            index,
            path: path.into(),
            label: format!("{path} fetched"),
            failed_label: format!("{path} fetch failed"),
            upstream_branch: "main".into(),
            target_ref: String::new(),
            old_sha: None,
            tag: String::new(),
            pinned_commit: String::new(),
        };
        let reports = crashed(&[member(0, "vendor/a"), member(2, "vendor/b")]);
        let summary: Vec<_> = reports
            .iter()
            .map(|(index, report)| (*index, report.failed, report.err.as_str()))
            .collect();
        assert_eq!(
            summary,
            [
                (0, true, "!!   vendor/a fetch failed"),
                (2, true, "!!   vendor/b fetch failed")
            ]
        );
    }

    #[test]
    fn shared_upstream_download_finishes_before_results_are_handled_without_refetching() {
        with_repository(|| {
            let url = upstream();
            let mut context = ExecutionContext::new();
            for path in ["vendor/a", "vendor/b"] {
                crate::clone::run(&mut context, &[url.clone(), path.into()]).unwrap();
            }
            let head = git(&["rev-parse", "HEAD"]);
            let old = git(&["-C", "upstream", "rev-parse", "HEAD"]);
            std::fs::write("upstream/file", "new\n").unwrap();
            git(&["-C", "upstream", "commit", "-qam", "new upstream"]);
            let new = git(&["-C", "upstream", "rev-parse", "HEAD"]);
            let mut repo = repo(&mut context);
            let selected = repo.selected.clone();
            let entries = repo.every_upstream_entry(&selected).unwrap();
            let plan = repo.prepare_fetch("main", &entries).unwrap();
            assert_eq!(plan.jobs.len(), 1);
            assert_eq!(plan.jobs[0].members.len(), 2);
            let reference = plan.jobs[0].members[0].target_ref.clone();
            assert_eq!(git(&["rev-parse", &reference]), old);
            let results = plan.download();
            assert_eq!(git(&["rev-parse", &reference]), new);
            assert_eq!(results.reports.len(), 2);
            for (path, report) in ["vendor/a", "vendor/b"].into_iter().zip(&results.reports) {
                assert!(!report.failed);
                assert!(report.out.contains(&format!("{path} fetched")));
                assert_eq!(
                    std::fs::read_to_string(format!("{path}/file")).unwrap(),
                    "old\n"
                );
            }
            assert_eq!(git(&["rev-parse", "HEAD"]), head);
            std::fs::rename("upstream", "upstream.offline").unwrap();
            assert!(results.finish(&mut repo).unwrap().0.is_empty());
            assert_eq!(git(&["rev-parse", &reference]), new);
            assert_eq!(git(&["rev-parse", "HEAD"]), head);
        });
    }

    #[test]
    fn failed_batch_retains_per_splice_failures_until_new_shared_key_is_cleaned_up() {
        with_repository(|| {
            let url = upstream();
            for path in ["vendor/a", "vendor/b"] {
                std::fs::create_dir_all(path).unwrap();
                std::fs::write(
                    format!("{path}/.splice"),
                    format!("[splice]\n id = {path}\n[upstream \"origin\"]\n url = {url}\n"),
                )
                .unwrap();
            }
            git(&["add", "vendor/a", "vendor/b"]);
            git(&["commit", "-qm", "mount splices"]);
            let mut context = ExecutionContext::new();
            let mut repo = repo(&mut context);
            let selected = repo.selected.clone();
            let entries = repo.every_upstream_entry(&selected).unwrap();
            assert!(repo.upstream_key(&url).unwrap().is_empty());
            let plan = repo.prepare_fetch("main", &entries).unwrap();
            assert_eq!(plan.jobs.len(), 1);
            assert_eq!(plan.new_keys.len(), 1);
            let key = repo.upstream_key(&url).unwrap();
            assert!(!key.is_empty());
            std::fs::rename("upstream", "upstream.offline").unwrap();
            let results = plan.download();
            assert!(results.reports.iter().all(|report| report.failed));
            assert_eq!(repo.upstream_key(&url).unwrap(), key);
            let (failures, event) = results.finish(&mut repo).unwrap();
            assert_eq!(failures, ["vendor/a", "vendor/b"]);
            assert!(repo.upstream_key(&url).unwrap().is_empty());
            assert_eq!(
                event,
                ExecutionEvent::AfterFetch {
                    fetched: vec![
                        FetchedUpstream {
                            path: "vendor/a".into(),
                            upstream: "origin".into(),
                            url: url.clone(),
                            failed: true
                        },
                        FetchedUpstream {
                            path: "vendor/b".into(),
                            upstream: "origin".into(),
                            url,
                            failed: true
                        },
                    ],
                }
            );
        });
    }
}
