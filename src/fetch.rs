//! git splice fetch.

use crate::args::parse_args;
use crate::repo::*;
use crate::util::*;

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

impl Repo {
    /// Fetches the upstreams of every given (distinct) entry in parallel, each
    /// (path, name) of an upstream of a splice, and each upstream once: splices
    /// with the same URL share their fetched refs, and two fetches into the
    /// same refs would fail on each other's locks. Prints what there is to say
    /// about each entry, in their order, and returns the paths that failed.
    pub fn fetch_all(&mut self, branch: &str, entries: &[(String, String)]) -> Res<FetchFailures> {
        // Before the fetches start in parallel, which would race to record keys.
        let mut groups: Vec<(String, String, Vec<usize>)> = Vec::new();
        for (i, (path, name)) in entries.iter().enumerate() {
            self.require_upstream_list(path)?;
            let url = self.url_of(path, name);
            let key = self.create_upstream_key(&url)?;
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

        let mut jobs: Vec<(String, String, Vec<String>, Vec<Member>)> = Vec::new();
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
                let pin = upstream_config(path, name, "default-pin");
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
                commits.push(splice_config(path, "commit", "HEAD"));
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
            jobs.push((key, url, commits, members));
        }

        let mut reports = vec![Report::default(); entries.len()];
        std::thread::scope(|scope| {
            let handles: Vec<_> = jobs
                .iter()
                .map(|(key, url, commits, members)| {
                    scope.spawn(move || fetch_shared_upstream(key, url, commits, members))
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

        let mut failures = Vec::new();
        for ((path, _), report) in entries.iter().zip(&reports) {
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
        Ok(failures)
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

pub fn run(argv: &[String]) -> Res<i32> {
    let args = parse_args(USAGE, "--upstream --branch --track --no-track", argv)?;
    args.require_branch_for_track()?;
    let mut repo = Repo::new(args);
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
