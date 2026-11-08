//! git splice pull.

use crate::args::parse_args;
use crate::merge::{apply_merge_options, MERGE_OPTIONS};
use crate::repo::*;
use crate::util::*;

pub const USAGE: &str = include_str!("usage/pull.txt");

pub fn run(argv: &[String]) -> Res<i32> {
    let args = parse_args(USAGE, &format!("{MERGE_OPTIONS} --recursive"), argv)?;
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

    // A recursive pull is one commit, made of its pulls once the last run
    // ends without a conflict. A run that stops leaves where it started.
    let fold = repo.args.has_flag("--recursive") && !repo.merge_rebase;
    if fold
        && git(&["rev-parse", "--quiet", "--verify", START])
            .q()
            .out()
            .is_none()
        && !git(&["update-ref", START, "HEAD"]).ok()
    {
        return fail(format!("{START} couldn't be updated"));
    }
    let mut status = 0;
    if !fetched.is_empty() && repo.merge_paths(&branch, "pull", &fetched).is_err() {
        status = 1;
    }
    if fold && !splice_in_progress() {
        if status == 0 {
            fold_pulls(&repo.args.paths)?;
        }
        if (status == 0 || !failures.is_empty()) && !git(&["update-ref", "-d", START]).ok() {
            return fail(format!("{START} couldn't be updated"));
        }
    }
    if !failures.is_empty() {
        log_err(format!("Not fetched: {}", failures.join(" ")));
        status = 1;
    }
    Ok(status)
}

const START: &str = "SPLICE_PULL_START";

/// Makes the commits since the recursive pull started one commit, whose
/// message lists them, if each is a pull: one that changed a .splice.
fn fold_pulls(given: &[String]) -> Res<()> {
    let range = format!("{START}..HEAD");
    let commits: Vec<String> = git(&["rev-list", "--reverse", "--first-parent", &range])
        .out()
        .unwrap_or_default()
        .lines()
        .map(str::to_string)
        .collect();
    if commits.len() < 2 {
        return Ok(());
    }
    for commit in &commits {
        let changed = git(&["diff-tree", "--no-commit-id", "--name-only", "-r", commit])
            .out()
            .unwrap_or_default();
        if !changed
            .lines()
            .any(|file| file == STATE_FILE || file.ends_with(&format!("/{STATE_FILE}")))
        {
            log_warn(format!(
                "{} isn't a pull -- the pulls since the recursive pull started stay separate commits",
                short(commit)
            ));
            return Ok(());
        }
    }
    let subjects = git(&["log", "--reverse", "--first-parent", "--format=%s", &range])
        .out()
        .unwrap_or_default();
    let message = format!(
        "splice: pull {} and the splices in it\n\n{subjects}\n",
        given.join(" ")
    );
    let tree = format!("{}^{{tree}}", "HEAD");
    let Some(folded) = git(&["commit-tree", &tree, "-p", START, "-m", &message]).out() else {
        return fail("the pulls couldn't be made one commit");
    };
    let head = git(&["rev-parse", "HEAD"]).out().unwrap_or_default();
    if !git(&[
        "update-ref",
        "-m",
        "splice: fold a recursive pull",
        "HEAD",
        &folded,
        &head,
    ])
    .ok()
    {
        return fail("the pulls couldn't be made one commit");
    }
    log_ok(format!(
        "{} pulls made one commit, {}",
        commits.len(),
        short(&folded)
    ));
    Ok(())
}
