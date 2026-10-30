//! git splice log.

use crate::args::parse_args;
use crate::diff::run_each_splice;
use crate::repo::*;
use crate::util::*;
use std::io::{BufRead, BufReader, Write};
use std::process::Stdio;

pub const USAGE: &str = include_str!("usage/log.txt");

const LOG_FORMAT: &str = "%m %h %s  (%an <%ae>)";
/// For --graph: the graph's nodes are the marks, and the full hash between \x01
/// and \x02 tells which commit a line is.
const GRAPH_FORMAT: &str = "%x01%H%x02%h %s  (%an <%ae>)";

/// Puts the labels (R) and (T) on the lines of the rebuild and the upstream
/// branch, and drops the full hash.
fn label_tip(line: &[u8], rebuilt: &str, target: &str) -> Vec<u8> {
    let start = line.iter().position(|&b| b == 1);
    let end = line.iter().position(|&b| b == 2);
    let (Some(start), Some(end)) = (start, end) else {
        return line.to_vec();
    };
    if end <= start {
        return line.to_vec();
    }
    let full = &line[start + 1..end];
    let rest = &line[end + 1..];
    let space = rest.iter().position(|&b| b == b' ').unwrap_or(rest.len());
    let label: &[u8] = if full == rebuilt.as_bytes() {
        b" (R)"
    } else if full == target.as_bytes() {
        b" (T)"
    } else {
        b""
    };
    [&line[..start], &rest[..space], label, &rest[space..]].concat()
}

fn splice_git_log(
    graph: bool,
    format: &str,
    rebuilt: &str,
    target: &str,
    rest: &[&str],
) -> Res<()> {
    let code = if graph {
        let format = format!("--format={GRAPH_FORMAT}");
        let mut args = vec!["log", "--graph", "--boundary", &format];
        args.extend_from_slice(rest);
        let mut command = git(&args).into_command();
        let mut child = command
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .spawn()
            .map_err(|_| Fail::Soft)?;
        let reader = BufReader::new(child.stdout.take().ok_or(Fail::Soft)?);
        let mut out = std::io::stdout();
        let mut reader_gone = false;
        for line in reader.split(b'\n') {
            let Ok(line) = line else { break };
            let mut labeled = label_tip(&line, rebuilt, target);
            labeled.push(b'\n');
            if out.write_all(&labeled).and_then(|()| out.flush()).is_err() {
                reader_gone = true;
                break;
            }
        }
        if reader_gone {
            // What a pager that was quit does to a shell's pipeline.
            let _ = child.kill();
            let _ = child.wait();
            141
        } else {
            child.wait().map_or(1, status_code)
        }
    } else {
        let format = format!("--format={format}");
        let mut args = vec!["log", &format];
        args.extend_from_slice(rest);
        git(&args).run()
    };
    match code {
        0 => Ok(()),
        code => Err(Fail::Code(code)),
    }
}

fn log_one(repo: &mut Repo, path: &str, branch: &str) -> Res<()> {
    repo.classify_splice(path, branch)?;
    let graph = repo.args.has_flag("--graph");
    let option = repo.upstream_option(path);
    let label = repo.c.upstream_label.clone();
    match repo.c.state {
        State::NeverFetched => {
            log_warn(format!(
                "{path}: not fetched -- run 'git splice fetch {option}{path}' first"
            ));
            return Err(Fail::Soft);
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
                        "{path}: upstream has no '{label}' branch, and its default branch{name} can't be compared with"
                    ));
                }
                Ok(()) => {}
            }
            let d = repo.d.clone();
            if d.rebuilt.is_empty() {
                return Ok(());
            }
            if d.default_ref.is_empty() {
                if d.default_branch == repo.c.upstream_branch {
                    log_step(format!("{path} (upstream has no '{label}' branch)"));
                } else {
                    log_step(format!(
                        "{path} (upstream has neither a '{label}' nor a '{}' branch)",
                        d.default_branch
                    ));
                }
                let format = LOG_FORMAT.replacen("%m", "<", 1);
                return splice_git_log(graph, &format, &d.rebuilt, "", &[&d.rebuilt]);
            }
            // As a PR from the branch push creates would: against the default
            // branch.
            log_step(format!(
                "{path} (upstream has no '{label}' branch -- compared with '{}')",
                d.default_branch
            ));
            let target = commit_of(&d.default_ref).unwrap_or_default();
            let range = format!("{}...{}", d.rebuilt, d.default_ref);
            return splice_git_log(
                graph,
                LOG_FORMAT,
                &d.rebuilt,
                &target,
                &["--left-right", "--cherry-mark", &range],
            );
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
        State::UpToDate if repo.c.rebuilt.is_empty() => return Ok(()),
        State::UnrelatedHistory if repo.c.rebuilt.is_empty() => {
            log_warn(format!("{path}: upstream and the splice share no history"));
            return Err(Fail::Soft);
        }
        _ => {}
    }
    log_step(format!("{path} ({label})"));
    let c = repo.c.clone();
    let target = commit_of(&c.target_ref).unwrap_or_default();
    let range = format!("{}...{}", c.rebuilt, c.target_ref);
    splice_git_log(
        graph,
        LOG_FORMAT,
        &c.rebuilt,
        &target,
        &["--left-right", "--cherry-mark", &range],
    )
}

pub fn run(argv: &[String]) -> Res<i32> {
    let mut repo = Repo::new(parse_args(USAGE, "--graph --upstream", argv)?);
    repo.open()?;
    repo.select_splices(Kind::Overview, "log")?;
    Ok(crate::pager::page_git_output(|| {
        run_each_splice(&mut repo, log_one)
    }))
}
