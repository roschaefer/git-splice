//! git splice pull.

use crate::args::parse_args;
use crate::levels::{conclude, refuse_pending};
use crate::merge::{apply_merge_options, synced_commit_here, MERGE_OPTIONS};
use crate::repo::*;
use crate::util::*;

pub const USAGE: &str = include_str!("usage/pull.txt");

pub fn run(argv: &[String]) -> Res<i32> {
    let args = parse_args(USAGE, &format!("{MERGE_OPTIONS} --continue --abort"), argv)?;
    args.require_one_splice_for_message()?;
    args.require_branch_for_track()?;
    let mut repo = Repo::new(args);
    apply_merge_options(&mut repo)?;
    repo.open()?;
    if let Some(concluded) = conclude(&mut repo) {
        return concluded;
    }
    // Before select_splices: a rebase in progress has detached HEAD.
    require_no_splice_in_progress()?;
    repo.select_splices(Kind::Explicit, "pull")?;
    let branch = repo.monorepo_branch.clone();
    let selected = repo.selected.clone();
    refuse_pending(&branch, &selected)?;

    // Nested splices are pulled one level down, which fetches them there, as
    // their .splice reads after the merges above; with --rebase, they merge
    // straight into the monorepo, like the others.
    let rebase = repo.args.has_flag("--rebase");
    let (through, direct): (Vec<String>, Vec<String>) = selected
        .iter()
        .cloned()
        .partition(|path| !rebase && splice_above_in("HEAD", path).is_some());
    let below = |path: &str, of: &[String]| {
        of.iter()
            .any(|above| path.starts_with(&format!("{above}/")))
    };
    // A splice below one pulled here, selected itself or not: the pull can
    // move its synced commit. The ones below a nested splice are fetched
    // one level down, with it.
    let below_direct: Vec<String> = repo
        .all_paths
        .iter()
        .filter(|path| !selected.contains(path) && below(path, &direct) && !below(path, &through))
        .cloned()
        .collect();
    // A splice above a nested one whose synced commit isn't here, e.g. in a
    // fresh clone: its rebuild is checked out, to pull one level down.
    let above: Vec<String> = repo
        .all_paths
        .iter()
        .filter(|path| !selected.contains(path))
        .filter(|path| {
            through
                .iter()
                .any(|inner| inner.starts_with(&format!("{path}/")))
        })
        .filter(|path| !synced_commit_here(path))
        .cloned()
        .collect();
    let mut entries = repo.used_upstream_entry(&above);
    // A synced commit that isn't here, e.g. one a pull above moved it to, may
    // be on any of the splice's upstreams.
    for path in &direct {
        if synced_commit_here(path) {
            entries.extend(repo.used_upstream_entry(std::slice::from_ref(path)));
        } else {
            entries.extend(repo.every_upstream_entry(std::slice::from_ref(path))?);
        }
    }
    entries.extend(repo.every_upstream_entry(&below_direct)?);
    let failures = repo.fetch_all(&branch, &entries)?;

    let mut fetched = Vec::new();
    for path in &selected {
        if failures.contains(path) {
            continue;
        }
        if let Some(failed) = first_above(path, &failures) {
            log_err(format!(
                "{path}: not pulled, since {failed} above it wasn't fetched"
            ));
            continue;
        }
        // Its pull could move the synced commit of the failed one to one that
        // wasn't fetched.
        if let Some(failed) = first_below(path, &failures) {
            log_err(format!(
                "{path}: not pulled, since {failed} below it wasn't fetched -- 'git splice merge {path}' merges what was fetched anyway"
            ));
            continue;
        }
        fetched.push(path.clone());
    }

    let before = git(&["rev-parse", "HEAD"]).out().unwrap_or_default();
    let mut status = 0;
    if !fetched.is_empty() && repo.merge_paths(&branch, "pull", &fetched).is_err() {
        status = 1;
    }
    // The splices below one pulled here whose .splice the pull changed, e.g.
    // to another URL: fetched from what it names now, so status and the next
    // pull find what they need.
    let changed: Vec<String> = below_direct
        .iter()
        .filter(|path| {
            let blob = |rev: &str| {
                git(&[
                    "rev-parse",
                    "--verify",
                    "--quiet",
                    &format!("{rev}:{path}/{STATE_FILE}"),
                ])
                .out()
            };
            blob("HEAD").is_some() && blob(&before) != blob("HEAD")
        })
        .cloned()
        .collect();
    let mut failures = failures;
    if !changed.is_empty() && !splice_in_progress() {
        let mut entries = Vec::new();
        for path in &changed {
            let old_urls: Vec<String> = repo
                .upstream_lists
                .get(path)
                .cloned()
                .unwrap_or_default()
                .iter()
                .map(|name| repo.url_of(path, name))
                .collect();
            if contained(repo.load_splice_upstream(path)).is_err() {
                failures.push(path.clone());
                continue;
            }
            // The upstreams it names now, but didn't before; all of them if
            // the synced commit isn't here, which any may have.
            let every = repo.every_upstream_entry(std::slice::from_ref(path))?;
            if synced_commit_here(path) {
                entries.extend(
                    every
                        .into_iter()
                        .filter(|(path, name)| !old_urls.contains(&repo.url_of(path, name))),
                );
            } else {
                entries.extend(every);
            }
        }
        failures.extend(repo.fetch_all(&branch, &entries)?);
        // A fetch by hash fails quietly when no upstream has the commit any
        // more, e.g. after a gc.
        for path in changed.iter().filter(|path| !failures.contains(path)) {
            if !synced_commit_here(path) {
                log_err(format!(
                    "{path}: its synced commit {}, from the pull above, isn't on its upstream any more",
                    short(&splice_config(path, "commit", "HEAD"))
                ));
                status = 1;
            }
        }
    }
    if !failures.is_empty() {
        log_err(format!("Not fetched: {}", failures.join(" ")));
        status = 1;
    }
    Ok(status)
}
