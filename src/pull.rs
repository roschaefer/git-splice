//! git splice pull.

use crate::args::parse_args;
use crate::merge::{apply_merge_options, MERGE_OPTIONS};
use crate::repo::*;
use crate::util::*;

pub const USAGE: &str = include_str!("usage/pull.txt");

pub fn run(argv: &[String]) -> Res<i32> {
    let args = parse_args(USAGE, MERGE_OPTIONS, argv)?;
    args.require_one_splice_for_message()?;
    args.require_branch_for_track()?;
    let mut repo = Repo::new(args);
    apply_merge_options(&mut repo)?;
    repo.open()?;
    // Before select_splices: a rebase in progress has detached HEAD.
    require_no_splice_in_progress()?;
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

    let mut status = 0;
    if !fetched.is_empty() && repo.merge_paths(&branch, "pull", &fetched).is_err() {
        status = 1;
    }
    if !failures.is_empty() {
        log_err(format!("Not fetched: {}", failures.join(" ")));
        status = 1;
    }
    Ok(status)
}
