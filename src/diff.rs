//! git splice diff.

use crate::args::parse_args;
use crate::repo::*;
use crate::util::*;

pub const USAGE: &str = include_str!("usage/diff.txt");

fn diff_one(repo: &mut Repo, path: &str, branch: &str) -> Res<()> {
    repo.classify_splice(path, branch)?;
    let option = repo.upstream_option(path);
    let mut old_tree = None;
    match repo.c.state {
        State::NeverFetched => {
            log_warn(format!(
                "{path}: not fetched -- run 'git splice fetch {option}{path}' first"
            ));
            return Err(Fail::Soft);
        }
        State::UpToDate | State::Pull => return Ok(()),
        State::UnrelatedHistory => {
            log_warn(format!(
                "{path}: upstream and the splice share no history -- no push diff available"
            ));
            return Err(Fail::Soft);
        }
        State::MissingSynced => {
            log_warn(format!("{path}: {}", repo.missing_synced_message(path)));
            return Err(Fail::Soft);
        }
        State::MissingPin => {
            return fail(format!(
                "{path}: {} isn't here -- run 'git splice fetch {option}{path}', or check that upstream has it",
                repo.c.target.description()
            ));
        }
        State::MissingBranch => {
            match repo.compare_with_default_branch(path) {
                Err(Fail::Hard) => return Err(Fail::Hard),
                Err(_) => {
                    let name = if repo.d.default_branch.is_empty() {
                        String::new()
                    } else {
                        format!(" '{}'", repo.d.default_branch)
                    };
                    return fail(format!(
                        "{path}: could not compare with upstream's default branch{name}"
                    ));
                }
                Ok(()) => {}
            }
            if repo.d.no_changes {
                return Ok(());
            }
            // As a PR shows it: from where R and the default branch meet.
            if !repo.d.default_ref.is_empty() {
                if let Some(base) = git(&["merge-base", &repo.d.rebuilt, &repo.d.default_ref]).out()
                {
                    old_tree = tree_of(&base);
                }
            }
        }
        State::Push | State::Diverged => old_tree = tree_of(&repo.c.target_ref),
    }
    let new_tree = contained(repo.content_tree("HEAD", path))?.unwrap_or_default();
    let old_tree = old_tree.unwrap_or_else(|| repo.empty_tree());
    log_step(path);
    let mut args = vec!["diff"];
    args.extend(repo.args.flags.iter().map(String::as_str));
    args.push(&old_tree);
    args.push(&new_tree);
    match git(&args).run() {
        0 => Ok(()),
        code => Err(Fail::Code(code)),
    }
}

/// Runs <step> for each splice, and reports the splices it failed for. Stops,
/// with status 141, as soon as SIGPIPE ends a step: a pager it writes to was
/// quit, and nobody reads the rest.
pub fn run_each_splice(repo: &mut Repo, step: fn(&mut Repo, &str, &str) -> Res<()>) -> i32 {
    let branch = repo.monorepo_branch.clone();
    let mut failures = Vec::new();
    for path in repo.selected.clone() {
        match step(repo, &path, &branch) {
            Ok(()) => {}
            Err(Fail::Code(141)) => return 141,
            Err(Fail::Hard) => return 1,
            Err(_) => failures.push(path),
        }
    }
    if !failures.is_empty() {
        log_err(format!("Failed: {}", failures.join(" ")));
        return 1;
    }
    0
}

pub fn run(argv: &[String]) -> Res<i32> {
    let mut repo = Repo::new(parse_args(USAGE, "--stat --upstream", argv)?);
    repo.open()?;
    repo.select_splices(Kind::Overview, "diff")?;
    Ok(crate::pager::page_git_output(|| {
        run_each_splice(&mut repo, diff_one)
    }))
}
