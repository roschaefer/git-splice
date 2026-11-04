//! Merges a nested splice one level at a time (#360): the rebuild of each
//! splice above it is checked out in a worktree, the repository that splice
//! comes from; the one-level merge runs in the innermost one, and
//! 'merge --rebuilt-commit' takes each result one level up, into the
//! monorepo last. A conflict stays in the worktree it came up in, as a merge
//! in progress, until 'pull --continue' or 'pull --abort'.

use crate::repo::*;
use crate::util::*;
use std::process::Command;

const PREFIX: &str = "splice-layer";

/// The monorepo branch as part of a ref name: one level, so the splice's path
/// can follow it.
fn branch_part(monorepo_branch: &str) -> String {
    monorepo_branch.replace('/', "%")
}

/// The temporary branch the worktree of the splice at <path> is on. The path
/// is one part of it: a branch can't be named like a folder of another, as
/// vendor/a would be for vendor/a/b.
fn layer_branch(monorepo_branch: &str, path: &str) -> String {
    format!(
        "{PREFIX}/{}/{}",
        branch_part(monorepo_branch),
        path.replace('/', "%")
    )
}

/// Where the worktree of the splice at <path> is: inside the repository's Git
/// directory, one folder per level, side by side, so none is in another.
fn layer_dir(monorepo_branch: &str, path: &str) -> Res<String> {
    let Some(common) = git(&["rev-parse", "--path-format=absolute", "--git-common-dir"]).out()
    else {
        return die("can't find the repository's Git directory");
    };
    Ok(format!(
        "{common}/splice-layers/{}/{}",
        branch_part(monorepo_branch),
        path.replace('/', "%")
    ))
}

/// The splices with a worktree left on <monorepo_branch>, outermost first: a
/// merge through them is in progress.
pub fn pending_levels(monorepo_branch: &str) -> Vec<String> {
    let prefix = format!("refs/heads/{PREFIX}/{}/", branch_part(monorepo_branch));
    let mut paths: Vec<String> = git(&["for-each-ref", "--format=%(refname)", &prefix])
        .out()
        .unwrap_or_default()
        .lines()
        .filter_map(|reference| {
            reference
                .strip_prefix(&prefix)
                .map(|path| path.replace('%', "/"))
        })
        .collect();
    paths.sort_by_key(|path| (path.matches('/').count(), path.clone()));
    paths
}

/// What to do about the merge through the levels in progress, for messages.
pub fn pending_hint(monorepo_branch: &str) -> Option<String> {
    let deepest = pending_levels(monorepo_branch).pop()?;
    let dir = layer_dir(monorepo_branch, &deepest).ok()?;
    // Shorter, and the same in every clone, where it's inside the monorepo.
    let shown = git(&["rev-parse", "--show-toplevel"])
        .out()
        .and_then(|top| dir.strip_prefix(&format!("{top}/")).map(str::to_string))
        .unwrap_or_else(|| dir.clone());
    Some(format!(
        "a merge through the levels waits in the worktree of {deepest} -- resolve the conflict in {shown}, 'git add' it there, then 'git splice pull --continue' (or 'git splice pull --abort')"
    ))
}

/// Ends the command if one of <paths> is, or is below or above, a splice a
/// merge through the levels is in progress for.
pub fn refuse_pending(monorepo_branch: &str, paths: &[String]) -> Res<()> {
    let pending = pending_levels(monorepo_branch);
    let blocked = paths.iter().any(|path| {
        pending.iter().any(|level| {
            path == level
                || path.starts_with(&format!("{level}/"))
                || level.starts_with(&format!("{path}/"))
        })
    });
    if blocked {
        if let Some(hint) = pending_hint(monorepo_branch) {
            return die(hint);
        }
    }
    Ok(())
}

/// Runs this program in <dir> with <args>; its output, with "ok   <inner>"
/// and the like reading <outer> instead, minus Git's advice for a conflict,
/// which the caller gives in its own words.
fn splice_in_dir(dir: &str, args: &[&str], inner: &str, outer: &str, verb: &str) -> (bool, String) {
    let Ok(exe) = std::env::current_exe() else {
        return (false, "can't find git-splice itself".to_string());
    };
    let Ok(output) = Command::new(exe).args(args).current_dir(dir).output() else {
        return (false, "can't run git-splice".to_string());
    };
    let mut text = String::from_utf8_lossy(&output.stdout).to_string();
    text.push_str(&String::from_utf8_lossy(&output.stderr));
    let shown: Vec<String> = text
        .lines()
        .filter(|line| !line.contains("-- resolve it, then 'git commit'"))
        .filter(|line| !line.contains("Failed: ") && !line.ends_with(": merge failed"))
        .map(|line| {
            let (mark, rest) = line.split_at(line.len().min(5));
            match rest.strip_prefix(inner) {
                Some(after) if after.starts_with([':', ' ']) => {
                    // The inner command merges; the outer one may pull.
                    let after = after.replacen(": merged ", &format!(": {} ", past(verb)), 1);
                    format!("{mark}{outer}{after}")
                }
                _ => line.to_string(),
            }
        })
        .collect();
    (output.status.success(), shown.join("\n"))
}

fn past(verb: &str) -> String {
    if verb == "pull" {
        "pulled".to_string()
    } else {
        "merged".to_string()
    }
}

fn print_lines(text: &str) {
    if !text.is_empty() {
        eprint_text(&format!("{text}\n"));
    }
}

fn merge_in_progress(dir: &str) -> bool {
    git(&[
        "-C",
        dir,
        "rev-parse",
        "--quiet",
        "--verify",
        "CHERRY_PICK_HEAD",
    ])
    .q()
    .ok()
}

/// Removes the worktree of the splice at <path> and its branch.
fn remove_level(monorepo_branch: &str, path: &str) -> Res<()> {
    let dir = layer_dir(monorepo_branch, path)?;
    if std::path::Path::new(&dir).exists() {
        git(&["worktree", "remove", "--force", &dir]).q().run();
    }
    git(&["worktree", "prune"]).q().run();
    git(&["branch", "-D", &layer_branch(monorepo_branch, path)])
        .q()
        .out();
    Ok(())
}

/// Removes every worktree left on <monorepo_branch>, for --abort.
pub fn abort(monorepo_branch: &str) -> Res<()> {
    let pending = pending_levels(monorepo_branch);
    if pending.is_empty() {
        return die("no merge through the levels in progress");
    }
    for path in pending.iter().rev() {
        remove_level(monorepo_branch, path)?;
    }
    log_ok(format!(
        "{}: merge through the levels aborted -- nothing reached the monorepo",
        pending.last().map_or("", String::as_str)
    ));
    Ok(())
}

/// The splices above <path>, outermost first.
fn levels_above(path: &str) -> Vec<String> {
    let mut levels = Vec::new();
    let mut at = path.to_string();
    while let Some(above) = splice_above_in("HEAD", &at) {
        levels.insert(0, above.clone());
        at = above;
    }
    levels
}

/// <path> as seen from inside the splice at <above>.
fn relative(path: &str, above: &str) -> String {
    path.strip_prefix(&format!("{above}/"))
        .unwrap_or(path)
        .to_string()
}

impl Repo {
    /// Merges nested splice <path> from <upstream_branch> one level at a time.
    pub fn merge_through_levels(
        &mut self,
        path: &str,
        branch: &str,
        verb: &str,
        upstream_branch: &str,
        message: &str,
    ) -> Res<()> {
        let levels = levels_above(path);
        let Some(outermost) = levels.first().cloned() else {
            return die(format!("{path}: no splice above it"));
        };
        if !git(&["diff", "--quiet", "HEAD", "--", &outermost]).q().ok() {
            return fail(format!(
                "{outermost} has uncommitted changes, which a {verb} through the levels wouldn't see -- commit or stash them first"
            ));
        }
        refuse_pending(branch, &[path.to_string()])?;

        // Each level: the rebuild of the splice, checked out, from inside
        // the level above it.
        let mut made: Vec<String> = Vec::new();
        let mut above_dir = String::new();
        let mut above_path = String::new();
        for level in &levels {
            let commit = if above_dir.is_empty() {
                self.rebuild_splice(level, "HEAD")?
            } else {
                let inner = relative(level, &above_path);
                let (ok, out) =
                    splice_in_dir(&above_dir, &["rebuild", &inner], &inner, level, "merge");
                if ok {
                    out.lines().last().map(str::to_string)
                } else {
                    print_lines(&out);
                    None
                }
            };
            let dir = layer_dir(branch, level)?;
            let created = commit.is_some_and(|commit| {
                git(&[
                    "worktree",
                    "add",
                    "-q",
                    "-b",
                    &layer_branch(branch, level),
                    &dir,
                    &commit,
                ])
                .q()
                .ok()
            });
            if !created {
                for done in made.iter().rev() {
                    remove_level(branch, done)?;
                }
                return fail(format!("{path}: can't check out the rebuild of {level}"));
            }
            made.push(level.clone());
            above_dir = dir;
            above_path = level.clone();
        }

        // The merge itself, one level down from the innermost splice above.
        let inner = relative(path, &above_path);
        let mut args = vec!["merge", "--branch", upstream_branch, "-m", message];
        if !self.args.upstream.is_empty() {
            args.extend(["--upstream", self.args.upstream.as_str()]);
        }
        if self.merge_bump {
            args.push("--bump");
        }
        if self.merge_no_fork_point {
            args.push("--no-fork-point");
        }
        args.push(&inner);
        let (ok, out) = splice_in_dir(&above_dir, &args, &inner, path, verb);
        print_lines(&out);
        if !ok {
            if merge_in_progress(&above_dir) {
                log_err(pending_hint(branch).unwrap_or_default());
                return Err(Fail::Soft);
            }
            for done in made.iter().rev() {
                remove_level(branch, done)?;
            }
            return fail(format!("{path}: {verb} failed"));
        }
        self.continue_levels(branch)
    }

    /// Takes the innermost level's commit one level up, until it's in the
    /// monorepo; stops at a conflict, which waits in the level it came up in.
    pub fn continue_levels(&mut self, branch: &str) -> Res<()> {
        loop {
            let mut pending = pending_levels(branch);
            let Some(deepest) = pending.pop() else {
                return Ok(());
            };
            let dir = layer_dir(branch, &deepest)?;
            let unmerged = git(&["-C", &dir, "diff", "--name-only", "--diff-filter=U"])
                .out()
                .unwrap_or_default();
            if !unmerged.is_empty() {
                return die(format!(
                    "{deepest}: {dir} still has conflicts -- resolve them, then 'git splice pull --continue'"
                ));
            }
            if merge_in_progress(&dir)
                && git(&["-C", &dir, "commit", "--quiet", "--no-edit"]).run() != 0
            {
                return die(format!(
                    "{deepest}: can't commit the resolved merge in {dir}"
                ));
            }
            let Some(commit) = git(&["-C", &dir, "rev-parse", "HEAD"]).out() else {
                return die(format!("{deepest}: {dir} has no commit"));
            };
            remove_level(branch, &deepest)?;
            match pending.last() {
                Some(above) => {
                    let above_dir = layer_dir(branch, above)?;
                    let inner = relative(&deepest, above);
                    let (ok, out) = splice_in_dir(
                        &above_dir,
                        &["merge", "--rebuilt-commit", &commit, &inner],
                        &inner,
                        &deepest,
                        "merge",
                    );
                    if !ok {
                        print_lines(&out);
                        if merge_in_progress(&above_dir) {
                            log_err(pending_hint(branch).unwrap_or_default());
                            return Err(Fail::Soft);
                        }
                        return die(format!(
                            "{deepest}: can't take it into {above} -- 'git splice pull --abort' gives up"
                        ));
                    }
                }
                None => {
                    // Into the monorepo: a conflict here is one like any other.
                    let message = git(&["log", "-1", "--format=%B", &commit])
                        .out()
                        .unwrap_or_default();
                    let given = std::mem::replace(&mut self.args.message, message);
                    let result = self.merge_rebuilt_commit_quietly(&deepest, &commit);
                    self.args.message = given;
                    return result;
                }
            }
        }
    }
}

/// --continue and --abort of merge and pull: None without them.
pub fn conclude(repo: &mut Repo) -> Option<Res<i32>> {
    let resume = repo.args.has_flag("--continue");
    let give_up = repo.args.has_flag("--abort");
    if !resume && !give_up {
        return None;
    }
    Some((|| {
        if resume && give_up {
            return die("--continue and --abort contradict each other -- give one");
        }
        if repo.args.all || !repo.args.paths.is_empty() {
            return die("--continue and --abort take no paths: they conclude the merge through the levels in progress");
        }
        let branch = current_branch()?;
        if give_up {
            abort(&branch)?;
            return Ok(0);
        }
        let Some(outermost) = pending_levels(&branch).first().cloned() else {
            return die("no merge through the levels in progress");
        };
        match repo.continue_levels(&branch) {
            Ok(()) => {
                log_ok(format!(
                    "{outermost}: took the merge through the levels into the monorepo"
                ));
                Ok(0)
            }
            Err(Fail::Hard) => Err(Fail::Hard),
            Err(_) => Ok(1),
        }
    })())
}
