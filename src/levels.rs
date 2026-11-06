//! Merges a nested splice one level at a time (#360): the rebuild of each
//! splice above it is checked out in a worktree, the repository that splice
//! comes from; the one-level merge runs in the innermost one, and
//! 'merge --rebuilt-commit' takes each result one level up, into the
//! monorepo last. A conflict stays in the worktree it came up in, as a merge
//! in progress, until 'pull --continue' or 'pull --abort'.

use crate::repo::*;
use crate::util::*;
use std::process::Command;

/// Set for a command run in a worktree of a level: the monorepo branch it
/// stands in for, which picks the upstream branches as in the monorepo.
pub const BRANCH_VARIABLE: &str = "GIT_SPLICE_BRANCH";

/// Set with BRANCH_VARIABLE: the default branch of the splice the worktree
/// stands in for, which the splices in it follow as in a clone of it.
pub const DEFAULT_VARIABLE: &str = "GIT_SPLICE_DEFAULT_BRANCH";

/// Set for the innermost level's command: "<head> <commit> <path>", the
/// monorepo's rebuild <commit> of the splice at <path>, as the level has it,
/// while its HEAD is <head>. A level's history starts where its splice was
/// made, and may lack what the monorepo's has; the monorepo's rebuild has it.
pub const REBUILD_VARIABLE: &str = "GIT_SPLICE_REBUILD";

/// The rebuild REBUILD_VARIABLE gives for the splice at <path>, while HEAD
/// is still the one it was given for.
pub fn given_rebuild(path: &str) -> Option<String> {
    let value = std::env::var(REBUILD_VARIABLE).ok()?;
    let mut parts = value.splitn(3, ' ');
    let (head, commit, given_path) = (parts.next()?, parts.next()?, parts.next()?);
    if given_path != path || git(&["rev-parse", "HEAD"]).out().as_deref() != Some(head) {
        return None;
    }
    Some(commit.to_string())
}

/// The branch and the default branch a level's worktree stands in for.
type Stand = (String, String);

const PREFIX: &str = "splice-layer";

/// A level's name, for its branch and its worktree's folder: generated from
/// the monorepo branch and the splice's path, so neither has to fit into a
/// ref or folder name. The level's config keeps both, for pending_levels.
fn level_name(monorepo_branch: &str, path: &str) -> String {
    let id = git(&["hash-object", "--stdin"])
        .input(format!("{monorepo_branch}\0{path}\0"))
        .out()
        .unwrap_or_default();
    id[..id.len().min(16)].to_string()
}

/// The temporary branch the worktree of the splice at <path> is on.
fn layer_branch(monorepo_branch: &str, path: &str) -> String {
    format!("{PREFIX}/{}", level_name(monorepo_branch, path))
}

/// Where the worktree of the splice at <path> is: inside the repository's Git
/// directory, one folder per level, side by side, so none is in another.
fn layer_dir(monorepo_branch: &str, path: &str) -> Res<String> {
    let Some(common) = git(&["rev-parse", "--path-format=absolute", "--git-common-dir"]).out()
    else {
        return die("can't find the repository's Git directory");
    };
    Ok(format!(
        "{common}/splice-layers/{}",
        level_name(monorepo_branch, path)
    ))
}

/// The splices with a worktree left on <monorepo_branch>, outermost first: a
/// merge through them is in progress.
pub fn pending_levels(monorepo_branch: &str) -> Vec<String> {
    // One level down, the merge through the levels is the caller's: the
    // worktree's command is one step of it, and goes no further down.
    if std::env::var_os(BRANCH_VARIABLE).is_some() {
        return Vec::new();
    }
    let prefix = format!("refs/heads/{PREFIX}/");
    let mut paths: Vec<String> = git(&["for-each-ref", "--format=%(refname:short)", &prefix])
        .out()
        .unwrap_or_default()
        .lines()
        .filter_map(|name| {
            let get = |key: &str| {
                git(&["config", "--get", &format!("branch.{name}.{key}")])
                    .q()
                    .out()
            };
            (get("spliceMonorepoBranch")? == monorepo_branch).then(|| get("splicePath"))?
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

/// Ends the command while a merge through the levels is in progress on
/// <monorepo_branch>, for any splice: like Git's own commands during a
/// rebase, until 'pull --continue' or 'pull --abort' concludes it.
pub fn refuse_pending(monorepo_branch: &str) -> Res<()> {
    match pending_hint(monorepo_branch) {
        Some(hint) => die(hint),
        None => Ok(()),
    }
}

/// <line> with each mention of the splice at <inner>, as a word of its own,
/// reading <outer>: the inner command names paths as its level has them.
fn outer_paths(line: &str, inner: &str, outer: &str) -> String {
    let mut out = String::new();
    let mut rest = line;
    while let Some(at) = rest.find(inner) {
        let before = rest[..at].chars().last();
        let after = rest[at + inner.len()..].chars().next();
        let starts = before.is_none_or(|c| matches!(c, ' ' | '\'' | '"' | '('));
        let ends = after.is_none_or(|c| matches!(c, ' ' | ':' | '/' | '\'' | '"' | ')' | ','));
        out.push_str(&rest[..at]);
        out.push_str(if starts && ends { outer } else { inner });
        rest = &rest[at + inner.len()..];
    }
    out.push_str(rest);
    out
}

/// Runs this program in <dir> with <args>, standing in for monorepo branch
/// <branch>; its output, with <inner> reading <outer>, minus Git's advice
/// for a conflict and the summary of failures, which the caller gives.
fn splice_in_dir(
    dir: &str,
    (branch, default): &Stand,
    args: &[&str],
    inner: &str,
    outer: &str,
) -> (bool, String) {
    splice_in_dir_with(dir, (branch, default), args, inner, outer, None)
}

fn splice_in_dir_with(
    dir: &str,
    (branch, default): (&String, &String),
    args: &[&str],
    inner: &str,
    outer: &str,
    rebuild: Option<String>,
) -> (bool, String) {
    let Ok(exe) = std::env::current_exe() else {
        return (false, "can't find git-splice itself".to_string());
    };
    let mut command = Command::new(exe);
    command
        .args(args)
        .current_dir(dir)
        .env(BRANCH_VARIABLE, branch)
        .env(DEFAULT_VARIABLE, default);
    if let Some(rebuild) = rebuild {
        command.env(REBUILD_VARIABLE, rebuild);
    }
    let Ok(output) = command.output() else {
        return (false, "can't run git-splice".to_string());
    };
    let mut text = String::from_utf8_lossy(&output.stdout).to_string();
    text.push_str(&String::from_utf8_lossy(&output.stderr));
    let shown: Vec<String> = text
        .lines()
        .filter(|line| !line.contains("-- resolve it, then 'git commit'"))
        .filter(|line| !line.contains("Failed: ") && !line.ends_with(" failed"))
        // git-splice's own lines, not Git's, whose paths are the
        // worktree's, where a conflict waits.
        .map(|line| {
            if ["ok   ", "!!   ", "??   ", "===  ", "  "]
                .iter()
                .any(|mark| line.starts_with(mark))
            {
                outer_paths(line, inner, outer)
            } else {
                line.to_string()
            }
        })
        .collect();
    (output.status.success(), shown.join("\n"))
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
    git(&[
        "config",
        "--remove-section",
        &stand_section(monorepo_branch, path),
    ])
    .q()
    .out();
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

/// The commit the worktree of the splice at <path> started at: the rebuild
/// it checked out.
fn level_start(monorepo_branch: &str, path: &str) -> Option<String> {
    git(&[
        "log",
        "-g",
        "--format=%H",
        &layer_branch(monorepo_branch, path),
    ])
    .out()?
    .lines()
    .last()
    .map(str::to_string)
}

/// Where the branch and default branch a level stands in for are kept, for
/// --continue in a later command: in the branch's config.
fn stand_section(monorepo_branch: &str, path: &str) -> String {
    format!("branch.{}", layer_branch(monorepo_branch, path))
}

fn record_stand(monorepo_branch: &str, level: &str, (branch, default): &Stand) {
    let section = stand_section(monorepo_branch, level);
    git(&[
        "config",
        &format!("{section}.spliceMonorepoBranch"),
        monorepo_branch,
    ])
    .q()
    .run();
    git(&["config", &format!("{section}.splicePath"), level])
        .q()
        .run();
    git(&["config", &format!("{section}.spliceStandsFor"), branch])
        .q()
        .run();
    git(&["config", &format!("{section}.spliceDefault"), default])
        .q()
        .run();
}

fn recorded_stand(monorepo_branch: &str, path: &str) -> Stand {
    let section = stand_section(monorepo_branch, path);
    let get = |key: &str| {
        git(&["config", "--get", &format!("{section}.{key}")])
            .q()
            .out()
            .unwrap_or_default()
    };
    (get("spliceStandsFor"), get("spliceDefault"))
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
    /// The message of <commit>, from the worktree of the splice at <level>,
    /// for the level above: a pull's default message names the splice as
    /// its level has it, and the monorepo's commit names its own path.
    fn outer_message(&self, level: &str, commit: &str) -> String {
        let message = git(&["log", "-1", "--format=%B", commit])
            .out()
            .unwrap_or_default();
        for verb in ["pull", "merge"] {
            let prefix = format!("splice: {verb} ");
            if let Some(rest) = message.strip_prefix(&prefix) {
                let token = rest.split(' ').next().unwrap_or_default();
                let full = format!("{level}/{token}");
                if self.all_paths.contains(&full) {
                    return format!("{prefix}{full}{}", &rest[token.len()..]);
                }
            }
        }
        message
    }

    /// Merges or pulls nested splice <path> one level at a time: the same
    /// command, one level down from the innermost splice above it, then up.
    pub fn merge_through_levels(&mut self, path: &str, branch: &str, verb: &str) -> Res<()> {
        let levels = levels_above(path);
        let Some(outermost) = levels.first().cloned() else {
            return die(format!("{path}: no splice above it"));
        };
        if !git(&["diff", "--quiet", "HEAD", "--", &outermost]).q().ok() {
            return fail(format!(
                "{outermost} has uncommitted changes, which a {verb} through the levels wouldn't see -- commit or stash them first"
            ));
        }
        refuse_pending(branch)?;

        // What each level's worktree stands in for, as a clone of its
        // upstream would be: on the branch the monorepo's branch maps to,
        // with the splice's default branch as its own.
        // As the merges above left them, not as the command started.
        for level in levels.iter().chain([&path.to_string()]) {
            quietly(|| contained(self.load_splice_upstream(level))).ok();
        }
        let stands: Vec<Stand> = levels
            .iter()
            .map(|level| {
                (
                    quietly(|| self.upstream_branch_for(level, branch, None))
                        .unwrap_or_else(|_| branch.to_string()),
                    quietly(|| self.splice_default_branch(level, None))
                        .unwrap_or_else(|_| self.monorepo_default_branch()),
                )
            })
            .collect();

        // The splice's history as the monorepo has it, for the merge one
        // level down: its level's may lack some, e.g. after an init around it.
        // Not before its synced commit is here: a pull fetches that one level
        // down, e.g. after a pull above moved it.
        let own_rebuild = if crate::merge::synced_commit_here(path) {
            quietly(|| contained(self.rebuild_splice(path, "HEAD")))
                .ok()
                .flatten()
        } else {
            None
        };

        // Each level: the rebuild of the splice, checked out, from inside
        // the level above it.
        let mut made: Vec<String> = Vec::new();
        let mut above_stand: Stand = Default::default();
        let mut above_dir = String::new();
        let mut above_path = String::new();
        for level in &levels {
            let commit = if above_dir.is_empty() {
                self.rebuild_splice(level, "HEAD")?
            } else {
                let inner = relative(level, &above_path);
                let (ok, out) = splice_in_dir(
                    &above_dir,
                    &above_stand,
                    &["rebuild", &inner],
                    &inner,
                    level,
                );
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
            above_stand = stands[made.len() - 1].clone();
            record_stand(branch, level, &above_stand);
        }

        // The merge itself, one level down from the innermost splice above.
        let inner = relative(path, &above_path);
        let mut args = vec![verb];
        // --branch, or the branch the monorepo tracks for the splice: the
        // worktree's branch has no tracked ones.
        let user_branch = if self.args.branch.is_empty() {
            self.tracked_branch(path, branch)
        } else {
            self.args.branch.clone()
        };
        let upstream = self.args.upstream.clone();
        let message = self.args.message.clone();
        if !user_branch.is_empty() {
            args.extend(["--branch", user_branch.as_str()]);
        }
        if !upstream.is_empty() {
            args.extend(["--upstream", upstream.as_str()]);
        }
        if !message.is_empty() {
            args.extend(["-m", message.as_str()]);
        }
        if self.merge_bump {
            args.push("--bump");
        }
        if self.merge_no_fork_point {
            args.push("--no-fork-point");
        }
        args.push(&inner);
        let rebuild = own_rebuild.and_then(|commit| {
            let head = git(&["-C", &above_dir, "rev-parse", "HEAD"]).out()?;
            Some(format!("{head} {commit} {inner}"))
        });
        let (ok, out) = splice_in_dir_with(
            &above_dir,
            (&above_stand.0, &above_stand.1),
            &args,
            &inner,
            path,
            rebuild,
        );
        print_lines(&out);
        if !ok {
            if merge_in_progress(&above_dir) {
                log_err(pending_hint(branch).unwrap_or_default());
                return Err(Fail::Soft);
            }
            for done in made.iter().rev() {
                remove_level(branch, done)?;
            }
            return Err(Fail::Soft);
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
            // Nothing came in at the innermost level: nothing to take up.
            if Some(&commit) == level_start(branch, &deepest).as_ref() {
                for level in pending_levels(branch).iter().rev() {
                    remove_level(branch, level)?;
                }
                return Ok(());
            }
            let message = self.outer_message(&deepest, &commit);
            // The level stays until its commit is taken up, or a conflict
            // above takes it over: until then, it's the commit's only branch.
            match pending.last() {
                Some(above) => {
                    let above_dir = layer_dir(branch, above)?;
                    let inner = relative(&deepest, above);
                    let (ok, out) = splice_in_dir(
                        &above_dir,
                        &recorded_stand(branch, above),
                        &["merge", "--rebuilt-commit", &commit, "-m", &message, &inner],
                        &inner,
                        &deepest,
                    );
                    if !ok {
                        print_lines(&out);
                        if merge_in_progress(&above_dir) {
                            remove_level(branch, &deepest)?;
                            log_err(pending_hint(branch).unwrap_or_default());
                            return Err(Fail::Soft);
                        }
                        return die(format!(
                            "{deepest}: can't take it into {above} -- fix that, then 'git splice pull --continue' (or 'git splice pull --abort')"
                        ));
                    }
                    remove_level(branch, &deepest)?;
                }
                None => {
                    // Into the monorepo: a conflict here is one like any other.
                    let given = std::mem::replace(&mut self.args.message, message);
                    let already = splice_in_progress();
                    let result = self.merge_rebuilt_commit_quietly(&deepest, &commit);
                    self.args.message = given;
                    if result.is_ok() || (!already && splice_in_progress()) {
                        remove_level(branch, &deepest)?;
                    }
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
