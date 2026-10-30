//! git splice status.

use crate::args::parse_args;
use crate::repo::*;
use crate::util::*;

pub const USAGE: &str = include_str!("usage/status.txt");

/// Ranks, most urgent first. Splices ranked QUIET_RANK or higher need nothing
/// from the user; they come last, after a blank line. Rank 6 is a quiet splice
/// with uncommitted changes.
const QUIET_RANK: u8 = 7;
const PROBLEM: u8 = 0;
const WARNING: u8 = 1;
const DIVERGED: u8 = 2;
const PULL: u8 = 3;
const PUSH: u8 = 4;
const NEW: u8 = 5;
const UP_TO_DATE: u8 = 7;
const UNCHANGED: u8 = 8;

struct Row {
    rank: u8,
    label: String,
    path: String,
    hint: String,
}

fn add_hint(hint: &mut String, more: &str) {
    if !hint.is_empty() {
        hint.push_str("; ");
    }
    hint.push_str(more);
}

fn classify_row(repo: &mut Repo, path: &str, branch: &str) -> Res<Row> {
    repo.classify_splice(path, branch)?;
    let option = repo.upstream_option(path);
    let c = repo.c.clone();
    let column = if c.upstream_label == branch {
        path.to_string()
    } else {
        format!("{path} -> {}", c.upstream_label)
    };
    let fetch_hint =
        format!("run 'git splice fetch {option}{path}', or check that upstream has it");
    let (mut rank, label, mut hint) = match c.state {
        State::NeverFetched => (
            WARNING,
            "?? never fetched".to_string(),
            format!("run 'git splice fetch {option}{path}'"),
        ),
        State::MissingBranch => {
            let compared = quietly(|| repo.compare_with_default_branch(path));
            match compared {
                // A refusal, which only rebuild errors are quiet for: says why.
                Err(Fail::Hard) => {
                    return repo.compare_with_default_branch(path).and(Err(Fail::Hard))
                }
                Err(_) => {
                    let hint = if repo.d.default_branch.is_empty() {
                        "upstream's default branch unknown".to_string()
                    } else {
                        format!(
                            "could not compare with upstream's '{}'",
                            repo.d.default_branch
                        )
                    };
                    (WARNING, "?? no upstream branch".to_string(), hint)
                }
                Ok(()) if repo.d.no_changes => (
                    UNCHANGED,
                    "unchanged, no upstream branch".to_string(),
                    String::new(),
                ),
                Ok(()) => {
                    let mut label = format!("new, ahead {}", repo.d.new_commits);
                    if repo.d.behind_commits != "0" {
                        label.push_str(&format!(", behind {}", repo.d.behind_commits));
                    }
                    (NEW, label, "push creates the branch".to_string())
                }
            }
        }
        State::MissingSynced => (
            WARNING,
            format!("?? synced commit {} isn't here", short(&c.synced)),
            fetch_hint,
        ),
        State::MissingPin => (
            PROBLEM,
            format!("!! {} isn't here", c.target.description()),
            fetch_hint,
        ),
        State::UpToDate => (UP_TO_DATE, "up to date".to_string(), String::new()),
        State::Push | State::Pull | State::Diverged => {
            // Ahead: commits of the rebuild R the upstream branch T lacks,
            // which push publishes. Behind: commits of T that R lacks, which
            // pull brings in. If they can't be counted, the state alone still
            // holds.
            let counts = git(&[
                "rev-list",
                "--left-right",
                "--count",
                &format!("{}...{}", c.rebuilt, c.target_ref),
            ])
            .q()
            .out();
            let label = if let Some(counts) = counts {
                let mut counts = counts.split_whitespace();
                let ahead = counts.next().unwrap_or("0");
                let behind = counts.next().unwrap_or("0");
                match c.state {
                    State::Push => format!("ahead {ahead}"),
                    State::Pull => format!("behind {behind}"),
                    _ => format!("ahead {ahead}, behind {behind}"),
                }
            } else {
                match c.state {
                    State::Push => "ahead",
                    State::Pull => "behind",
                    _ => "diverged",
                }
                .to_string()
            };
            let rank = match c.state {
                State::Push => PUSH,
                State::Pull => PULL,
                _ => DIVERGED,
            };
            (rank, label, String::new())
        }
        State::UnrelatedHistory => (
            PROBLEM,
            "!! unrelated history".to_string(),
            format!("see 'git splice merge {option}{path}' for options"),
        ),
    };
    if !repo.tracked_branch(path, branch).is_empty() {
        add_hint(&mut hint, &format!("tracked on {branch}, local"));
    }
    let uncommitted = match repo.has_uncommitted_changes(path) {
        Uncommitted::Changes => "uncommitted changes",
        Uncommitted::Failed => "could not check for uncommitted changes (git status failed)",
        Uncommitted::NoChanges => "",
    };
    if !uncommitted.is_empty() {
        add_hint(&mut hint, uncommitted);
        // Uncommitted changes need the user even where the splice doesn't.
        rank = rank.min(QUIET_RANK - 1);
    }
    Ok(Row {
        rank,
        label,
        path: column,
        hint,
    })
}

fn print_rows(rows: &[Row]) {
    let tty = crate::pager::stdout_is_terminal();
    let colorbool = git(&[
        "config",
        "--get-colorbool",
        "color.status",
        if tty { "true" } else { "false" },
    ])
    .out();
    let (dim, reset) = if colorbool.as_deref() == Some("true") {
        ("\x1b[2m", "\x1b[m")
    } else {
        ("", "")
    };
    let width = |text: &str| text.chars().count();
    let label_width = rows.iter().map(|r| width(&r.label)).max().unwrap_or(0);
    let path_width = rows
        .iter()
        .filter(|r| !r.hint.is_empty())
        .map(|r| width(&r.path))
        .max()
        .unwrap_or(0);
    let mut shown_rank = None;
    for rank in 0..=8 {
        for row in rows.iter().filter(|row| row.rank == rank) {
            if shown_rank.is_some_and(|shown| shown < QUIET_RANK) && rank >= QUIET_RANK {
                say("");
            }
            shown_rank = Some(rank);
            let line = if row.hint.is_empty() {
                format!("  {:label_width$}  {}", row.label, row.path)
            } else {
                format!(
                    "  {:label_width$}  {:path_width$}  {}",
                    row.label, row.path, row.hint
                )
            };
            if rank >= QUIET_RANK {
                say(format!("{dim}{line}{reset}"));
            } else {
                say(line);
            }
        }
    }
}

pub fn run(argv: &[String]) -> Res<i32> {
    let mut repo = Repo::new(parse_args(USAGE, "--upstream", argv)?);
    repo.open()?;
    if repo.all_paths.is_empty() && repo.args.paths.is_empty() {
        log_ok("no splices -- 'git splice clone <url> <path>' adds one");
        return Ok(0);
    }
    repo.select_splices(Kind::Overview, "status")?;
    let branch = repo.monorepo_branch.clone();
    let selected = repo.selected.clone();
    repo.load_uncommitted_changes(&selected);
    let mut rows = Vec::new();
    for path in &selected {
        rows.push(classify_row(&mut repo, path, &branch)?);
    }
    say(format!("On branch {branch}\n"));
    print_rows(&rows);
    Ok(0)
}
