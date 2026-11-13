//! git splice fetch.

use crate::args::parse_args;
use crate::context::ExecutionContext;
use crate::execution::{ExecutionEvent, FetchedUpstream};
use crate::repo::*;
use crate::util::*;
use std::collections::{HashMap, HashSet};

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
    for (i, member) in members.iter().enumerate() {
        let new_sha = git(&["rev-parse", "--verify", "--quiet", &member.target_ref]).out();
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
    /// about each entry, the splices in the order of their first entry, and
    /// returns the paths that failed.
    pub fn fetch_all(&mut self, branch: &str, entries: &[(String, String)]) -> Res<FetchFailures> {
        let mut walk = FetchWalk::new(self, branch, entries, Descend::Never);
        while let Some(plan) = walk.plan(self)? {
            let results = plan.download(self.context);
            walk.finish(self, results)?;
        }
        Ok(walk.failures)
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
                let tag = if is_commit_id(&pin) {
                    commits.push(pin.clone());
                    String::new()
                } else {
                    pin.clone()
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
}

impl FetchPlan {
    /// One plan for both: an upstream in both is fetched once.
    fn combine(mut self, other: FetchPlan) -> FetchPlan {
        let offset = self.entries.len();
        self.entries.extend(other.entries);
        for mut job in other.jobs {
            for member in &mut job.members {
                member.index += offset;
            }
            match self.jobs.iter_mut().find(|known| known.key == job.key) {
                Some(known) => {
                    known.commits.extend(job.commits);
                    for member in job.members {
                        // Reported once: its entry stays without a report.
                        if !known.members.iter().any(|m| m.path == member.path) {
                            known.members.push(member);
                        }
                    }
                }
                None => self.jobs.push(job),
            }
        }
        for key in other.new_keys {
            if !self.new_keys.contains(&key) {
                self.new_keys.push(key);
            }
        }
        self
    }

    pub(crate) fn download(self, context: &mut ExecutionContext) -> FetchResults {
        let (results, event) = self.download_event();
        if context.observing() {
            context.emit(event);
        }
        results
    }

    pub(crate) fn download_event(self) -> (FetchResults, ExecutionEvent) {
        let mut reports = vec![Report::default(); self.entries.len()];
        std::thread::scope(|scope| {
            let handles: Vec<_> = self
                .jobs
                .iter()
                .map(|job| {
                    scope.spawn(move || {
                        fetch_shared_upstream(&job.key, &job.url, &job.commits, &job.members)
                    })
                })
                .collect();
            for handle in handles {
                if let Ok(done) = handle.join() {
                    for (index, report) in done {
                        reports[index] = report;
                    }
                }
            }
        });

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

        (
            FetchResults {
                plan: self,
                reports,
            },
            ExecutionEvent::AfterFetch {
                fetched: fetched.into_iter().map(|(_, entry)| entry).collect(),
            },
        )
    }
}

impl FetchResults {
    pub(crate) fn finish(self, repo: &mut Repo) -> Res<FetchFailures> {
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
            if job.members.iter().any(|m| !self.reports[m.index].failed) {
                repo.fetched_urls.insert(job.url.clone());
            }
        }
        for job in &self.plan.jobs {
            if self.plan.new_keys.contains(&job.key)
                && job.members.iter().all(|m| self.reports[m.index].failed)
            {
                repo.forget_upstream_key(&job.key)?;
            }
        }
        Ok(failures)
    }
}

/// Which fetched splices the walk descends from: the state files in the
/// upstream commit each one syncs with name what the next level fetches.
#[derive(Clone, Copy, PartialEq, Debug)]
pub(crate) enum Descend {
    /// Only what the monorepo's state files name: git splice fetch.
    Never,
    /// From the selected splices: a pull merges only them.
    Selected,
    /// From every splice: a recursive pull merges each one.
    All,
}

/// A splice the walk fetches for, as one state file describes it.
#[derive(Clone)]
struct Node {
    path: String,
    /// The commit or tree whose state files describe it and the splices
    /// around it: HEAD, or a tree of state files only.
    rev: String,
    /// The upstreams to fetch.
    names: Vec<String>,
}

/// Fetches level by level, before anything is merged. The first level is
/// what the monorepo's state files name. Each next one is what the state
/// files in the upstream commits just fetched name: the commits a pull is
/// about to merge, with the splices inside them. A splice whose state file
/// a merge may leave in either version is fetched for both.
pub(crate) struct FetchWalk {
    branch: String,
    descend: Descend,
    level: Vec<Node>,
    first: bool,
    /// (path, blob) of each state file fetched for.
    seen: HashSet<(String, String)>,
    /// Paths whose fetch failed, or whose synced commit isn't here after it.
    pub failures: FetchFailures,
}

impl FetchWalk {
    pub(crate) fn new(
        repo: &Repo,
        branch: &str,
        entries: &[(String, String)],
        descend: Descend,
    ) -> Self {
        let mut level: Vec<Node> = Vec::new();
        for (path, name) in entries {
            match level.iter_mut().find(|node| node.path == *path) {
                Some(node) => node.names.push(name.clone()),
                None => level.push(Node {
                    path: path.clone(),
                    rev: "HEAD".to_string(),
                    names: vec![name.clone()],
                }),
            }
        }
        // The monorepo's state files: fetched for, or not needed.
        let seen = if descend == Descend::Never {
            HashSet::new()
        } else {
            state_file_entries(repo, "HEAD")
                .into_iter()
                .filter_map(|(file, blob)| {
                    Some((
                        file.strip_suffix(&format!("/{STATE_FILE}"))?.to_string(),
                        blob,
                    ))
                })
                .collect()
        };
        Self {
            branch: branch.to_string(),
            descend,
            level,
            first: true,
            seen,
            failures: Vec::new(),
        }
    }

    /// What to download for the current level, or nothing once the walk is
    /// done. Skips a level with nothing to download.
    pub(crate) fn plan(&mut self, repo: &mut Repo) -> Res<Option<FetchPlan>> {
        while !self.level.is_empty() {
            let mut combined: Option<FetchPlan> = None;
            let mut revs: Vec<String> = Vec::new();
            for node in &self.level {
                if !revs.contains(&node.rev) {
                    revs.push(node.rev.clone());
                }
            }
            for rev in revs {
                let entries: Vec<(String, String)> = self
                    .level
                    .iter()
                    .filter(|node| node.rev == rev)
                    .flat_map(|node| {
                        node.names
                            .iter()
                            .map(|name| (node.path.clone(), name.clone()))
                    })
                    .collect();
                let plan = if self.first {
                    repo.prepare_fetch(&self.branch, &entries)?
                } else {
                    let branch = self.branch.clone();
                    repo.with_state_rev(&rev, |repo| {
                        let needed: Vec<(String, String)> = entries
                            .iter()
                            .filter(|(path, name)| repo.fetch_needed(path, name))
                            .cloned()
                            .collect();
                        repo.prepare_fetch(&branch, &needed)
                    })?
                };
                combined = Some(match combined {
                    Some(known) => known.combine(plan),
                    None => plan,
                });
            }
            match combined {
                Some(plan) if !plan.jobs.is_empty() => return Ok(Some(plan)),
                _ => self.next_level(repo, &[])?,
            }
        }
        Ok(None)
    }

    /// Reports the level's downloads and finds the next level.
    pub(crate) fn finish(&mut self, repo: &mut Repo, results: FetchResults) -> Res<()> {
        let failed = results.finish(repo)?;
        self.next_level(repo, &failed)
    }

    fn next_level(&mut self, repo: &mut Repo, failed: &[String]) -> Res<()> {
        for path in failed {
            if !self.failures.contains(path) {
                self.failures.push(path.clone());
            }
        }
        let level = std::mem::take(&mut self.level);
        let first = std::mem::replace(&mut self.first, false);
        let mut next: Vec<Node> = Vec::new();
        let mut entries_of: HashMap<String, Vec<(String, String)>> = HashMap::new();
        let mut entries = |repo: &Repo, rev: &str| {
            entries_of
                .entry(rev.to_string())
                .or_insert_with(|| state_file_entries(repo, rev))
                .clone()
        };
        for node in level {
            if failed.contains(&node.path) {
                continue;
            }
            // A synced commit the monorepo records but no upstream has any
            // more is merge's to report, as it is without a walk.
            if !first {
                let synced = splice_config(&node.path, "commit", &node.rev);
                if !synced.is_empty() && !commit_here(&synced) {
                    log_err(format!(
                        "{}: its synced commit {}, from a pull above, isn't on its upstream any more",
                        node.path,
                        short(&synced)
                    ));
                    if !self.failures.contains(&node.path) {
                        self.failures.push(node.path.clone());
                    }
                    continue;
                }
            }
            let descends = match self.descend {
                Descend::Never => false,
                Descend::Selected => first && repo.selected.contains(&node.path),
                Descend::All => true,
            };
            // A copy of a splice it's inside brings in another copy below,
            // and that one the next: the merge stops at it, by its id.
            if !descends || copy_of_splice_above(&node.rev, &node.path) {
                continue;
            }
            let branch = self.branch.clone();
            let target = if first {
                quietly(|| repo.resolve_upstream_target(&node.path, &branch))
            } else {
                repo.with_state_rev(&node.rev, |repo| {
                    quietly(|| {
                        repo.require_upstream_list(&node.path)?;
                        repo.resolve_upstream_target(&node.path, &branch)
                    })
                })
            };
            let Some(commit) = target.ok().and_then(|t| commit_of(&t.reference)) else {
                continue;
            };
            let below = format!("{}/", node.path);
            let mut files: Vec<(String, String)> = entries(repo, &node.rev)
                .into_iter()
                .filter(|(file, _)| !file.starts_with(&below))
                .collect();
            files.extend(
                entries(repo, &commit)
                    .into_iter()
                    .map(|(file, blob)| (format!("{below}{file}"), blob)),
            );
            let Some(rev) = tree_of_files(&files) else {
                continue;
            };
            let found: Vec<String> = files
                .iter()
                .filter_map(|(file, blob)| {
                    let path = file.strip_suffix(&format!("/{STATE_FILE}"))?;
                    (path.starts_with(&below) && self.seen.insert((path.to_string(), blob.clone())))
                        .then(|| path.to_string())
                })
                .collect();
            let loaded = repo.with_state_rev(&rev, |repo| {
                found
                    .into_iter()
                    .map(|path| {
                        let names = contained(repo.require_upstream_list(&path))
                            .map(|()| repo.upstream_lists[&path].clone());
                        (path, names)
                    })
                    .collect::<Vec<_>>()
            });
            for (path, names) in loaded {
                match names {
                    Ok(names) => next.push(Node {
                        path,
                        rev: rev.clone(),
                        names,
                    }),
                    // Its merge would refuse it: nothing to merge it with.
                    Err(_) => {
                        if !self.failures.contains(&path) {
                            self.failures.push(path);
                        }
                    }
                }
            }
        }
        self.level = next;
        Ok(())
    }
}

impl Repo<'_> {
    /// Upstream <name> of splice <path> needs a fetch: this command hasn't
    /// fetched it, or not the synced commit or pin the state file records.
    fn fetch_needed(&mut self, path: &str, name: &str) -> bool {
        if self.require_upstream_list(path).is_err() {
            return false;
        }
        let url = self.url_of(path, name);
        if !self.fetched_urls.contains(&url) {
            return true;
        }
        let synced = splice_config(path, "commit", &self.state_rev);
        let pin = self.upstream_setting(path, name, "default-pin");
        let key = self.upstream_key(&url).unwrap_or_default();
        (!synced.is_empty() && !commit_here(&synced))
            || (is_commit_id(&pin) && !commit_here(&pin))
            || (!pin.is_empty()
                && !is_commit_id(&pin)
                && !ref_exists(&format!("refs/splices/{key}/tags/{pin}")))
    }
}

/// Splice <path> in <rev> has the id of a splice it's inside.
fn copy_of_splice_above(rev: &str, path: &str) -> bool {
    let id = splice_config(path, "id", rev);
    let mut above = path;
    while let Some((dir, _)) = above.rsplit_once('/') {
        above = dir;
        if !id.is_empty() && splice_config(above, "id", rev) == id {
            return true;
        }
    }
    false
}

/// Each (file, blob) of a state file in <rev>, from one diff-tree.
fn state_file_entries(repo: &Repo, rev: &str) -> Vec<(String, String)> {
    let spec = format!(":(top,glob)**/{STATE_FILE}");
    let output = git(&[
        "diff-tree",
        "-r",
        "-z",
        "--no-renames",
        &repo.empty_tree(),
        rev,
        "--",
        &spec,
    ])
    .q()
    .bytes()
    .unwrap_or_default();
    // ":<old mode> <new mode> <old blob> <new blob> A", then the file.
    nul_fields(&output)
        .chunks(2)
        .filter_map(|pair| {
            let blob = pair.first()?.split(' ').nth(3)?.to_string();
            Some((pair.get(1)?.clone(), blob))
        })
        .collect()
}

/// A tree of just the given (file, blob) state files.
fn tree_of_files(files: &[(String, String)]) -> Option<String> {
    let index = Temp::new();
    let lines: String = files
        .iter()
        .map(|(file, blob)| format!("100644 {blob}\t{file}\n"))
        .collect();
    let indexed = |args: &[&str]| git(args).env("GIT_INDEX_FILE", &index.path);
    if !indexed(&["update-index", "--index-info"]).input(lines).ok() {
        return None;
    }
    indexed(&["write-tree"]).out()
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
    let mut failures = fetch_failures.clone();

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
                    Err(_) => failures.push(path.clone()),
                    Ok(()) => {}
                }
            } else {
                log_err(format!(
                    "{path}: upstream has no '{wanted}' branch to track"
                ));
                failures.push(path.clone());
            }
        } else if no_track {
            match repo.untrack_branch(path, &branch) {
                Err(Fail::Hard) => return Err(Fail::Hard),
                Err(_) => failures.push(path.clone()),
                Ok(()) => {}
            }
        }
    }
    if !failures.is_empty() {
        log_err(format!("Failed: {}", failures.join(" ")));
        return Ok(1);
    }
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::test_repo::{git, with_repository};

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
            let results = plan.download(repo.context);
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
            assert!(results.finish(&mut repo).unwrap().is_empty());
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
            let events = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
            let recorded = events.clone();
            context.set_observer(move |event| {
                assert!(!git(&["config", "--get-regexp", "^splice\\..*\\.url$"]).is_empty());
                recorded.lock().unwrap().push(event.clone());
            });
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
            let results = plan.download(repo.context);
            assert!(results.reports.iter().all(|report| report.failed));
            assert_eq!(repo.upstream_key(&url).unwrap(), key);
            assert_eq!(results.finish(&mut repo).unwrap(), ["vendor/a", "vendor/b"]);
            assert!(repo.upstream_key(&url).unwrap().is_empty());
            let observed = events.lock().unwrap();
            assert_eq!(
                *observed,
                vec![ExecutionEvent::AfterFetch {
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
                }],
                "observed events:\n{observed:#?}"
            );
        });
    }
}
