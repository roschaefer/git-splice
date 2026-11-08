//! git splice pull.

use crate::args::parse_args;
use crate::merge::{apply_merge_options, MERGE_OPTIONS};
use crate::message::{Message, KNOWN};
use crate::repo::*;
use crate::util::*;

pub const USAGE: &str = include_str!("usage/pull.txt");

pub fn run(argv: &[String]) -> Res<i32> {
    let args = parse_args(
        USAGE,
        &format!("{MERGE_OPTIONS} --recursive --exec --continue-from"),
        argv,
    )?;
    if !args.exec.is_empty() || !args.continue_from.is_empty() {
        return crate::checkpoint::run("pull", args);
    }
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
    repo.select_splices(Kind::Explicit, "pull")?;
    let branch = repo.monorepo_branch.clone();
    let (fetched, failures) = fetch_for_pull(&mut repo)?;

    // A recursive pull is one commit per splice it starts from, made of its
    // pulls once the last run ends without a conflict; pull --all starts
    // from each splice no other is around. A run that stops leaves where it
    // started, which a later run goes on from only while HEAD still descends
    // from it: not after the branch was reset past it, e.g. after an abort.
    let fold = (repo.args.has_flag("--recursive") || repo.args.all) && !repo.merge_rebase;
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
    if fold && !goes_on && !git(&["update-ref", START, "HEAD"]).ok() {
        return fail(format!("{START} couldn't be updated"));
    }
    let mut status = 0;
    if !fetched.is_empty() && repo.merge_paths(&branch, "pull", &fetched).is_err() {
        status = 1;
    }
    if fold && !splice_in_progress() {
        if status == 0 {
            fold_pulls(&tops)?;
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

pub(crate) fn fetch_for_pull(repo: &mut Repo) -> Res<(Vec<String>, Vec<String>)> {
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

    Ok((fetched, failures))
}

const START: &str = "SPLICE_PULL_START";

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
pub(crate) fn fold_pulls(tops: &[String]) -> Res<()> {
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
