//! git splice pull.

use crate::args::parse_args;
use crate::merge::{apply_merge_options, MERGE_OPTIONS};
use crate::message::{Message, KNOWN};
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

    // A recursive pull is one commit per splice it starts from, made of its
    // pulls once the last run ends without a conflict; pull --all starts
    // from each splice no other is around. A run that stops leaves where it
    // started, which a later run goes on from only while HEAD still descends
    // from it: not after the branch was reset past it, e.g. after an abort.
    let fold = recursive;
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
    if rebase_tree && resumed.is_none() {
        for path in &fetched {
            if repo.pull_to_rebase(path, &branch)? {
                rewinds = true;
            }
        }
    }
    if rewinds {
        rewind_to_last_pull(&tops, &branch)?;
    } else if fold && !goes_on && !git(&["update-ref", START, "HEAD"]).ok() {
        return fail(format!("{START} couldn't be updated"));
    }
    let rebasing = rebase_under_way()?.is_some();
    let mut status = 0;
    if !fetched.is_empty() && repo.merge_paths(&branch, "pull", &fetched).is_err() {
        status = 1;
    }
    if fold && !splice_in_progress() {
        if status == 0 {
            fold_pulls(&tops)?;
        }
        if status == 0 || !failures.is_empty() {
            if rebasing {
                if !replay_own_commits(&branch)? {
                    status = 1;
                }
            } else if !git(&["update-ref", "-d", START]).ok() {
                return fail(format!("{START} couldn't be updated"));
            }
        }
    }
    if rebasing && rebase_under_way()?.is_some() {
        log_err(format!(
            "The pulls are on a detached HEAD, '{branch}' is as it was -- re-run pull to go on, or 'git switch {branch}' to give up"
        ));
    }
    if !failures.is_empty() {
        log_err(format!("Not fetched: {}", failures.join(" ")));
        status = 1;
    }
    Ok(status)
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

#[cfg(test)]
mod tests {
    use super::*;

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
