//! git splice -- keep folders of a monorepo in sync with their own upstream
//! repositories, in both directions.
//!
//! A splice is a folder with a committed .splice file that names its upstream
//! URL and the upstream commit it last matched. Every splice syncs with the
//! upstream branch named like the monorepo's current branch. See
//! docs/design/README.md.

mod args;
mod clone;
mod diff;
mod fetch;
mod init;
mod key;
mod log;
mod merge;
mod pager;
mod pull;
mod push;
mod rebuild;
mod repo;
mod state;
mod status;
mod util;

use args::parse_args;
use repo::Repo;
use std::process::ExitCode;
use util::*;

const USAGE: &str = include_str!("usage/top.txt");
const USAGE_REBUILD: &str = include_str!("usage/rebuild.txt");
const USAGE_BOUNDARY: &str = include_str!("usage/boundary.txt");

/// Git 2.40 is the oldest version the tests run against.
fn require_git_version() -> Res<()> {
    let version = git(&["--version"]).out().unwrap_or_default();
    let numbers = version.strip_prefix("git version ").unwrap_or("");
    let mut numbers = numbers.split('.').map(|n| n.parse::<u32>().unwrap_or(0));
    let major = numbers.next().unwrap_or(0);
    let minor = numbers.next().unwrap_or(0);
    if major < 2 || (major == 2 && minor < 40) {
        return die(format!("git-splice requires Git >= 2.40 (found {version})"));
    }
    Ok(())
}

fn run_rebuild(argv: &[String]) -> Res<i32> {
    let args = parse_args(USAGE_REBUILD, "", argv)?;
    args.require(USAGE_REBUILD, "rebuild", 1, 1)?;
    let path = normalize_path(&args.paths[0]);
    let mut repo = Repo::new(args);
    repo.open()?;
    repo.require_splice(&path)?;
    match repo.rebuild_splice(&path, "HEAD")? {
        Some(rebuilt) => {
            say(rebuilt);
            Ok(0)
        }
        None => die(format!("{path}: has no content yet -- nothing to rebuild")),
    }
}

fn run_boundary(argv: &[String]) -> Res<i32> {
    let args = parse_args(USAGE_BOUNDARY, "", argv)?;
    args.require(USAGE_BOUNDARY, "boundary", 1, 1)?;
    let path = normalize_path(&args.paths[0]);
    let mut repo = Repo::new(args);
    repo.open()?;
    repo.require_splice(&path)?;
    if let Some(start) = repo.splice_start(&path, "HEAD")? {
        say(start);
    }
    Ok(0)
}

fn dispatch(argv: &[String]) -> Res<i32> {
    require_git_version()?;
    let Some(command) = argv.first() else {
        eprint_text(USAGE);
        return Ok(1);
    };
    let rest = &argv[1..];
    match command.as_str() {
        "-h" | "--help" => {
            say(USAGE.trim_end_matches('\n'));
            Ok(0)
        }
        "--version" => {
            say(format!("git splice version {}", env!("CARGO_PKG_VERSION")));
            Ok(0)
        }
        "status" => status::run(rest),
        "diff" => diff::run(rest),
        "log" => log::run(rest),
        "key" => key::run(rest),
        "clone" => clone::run(rest),
        "init" => init::run(rest),
        "push" => push::run(rest),
        "fetch" => fetch::run(rest),
        "merge" => merge::run(rest),
        "pull" => pull::run(rest),
        "rebuild" => run_rebuild(rest),
        "boundary" => run_boundary(rest),
        _ => {
            log_err(format!("unknown command: {command}"));
            eprint_text(USAGE);
            Ok(1)
        }
    }
}

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args_os()
        .skip(1)
        .map(|arg| arg.to_string_lossy().into_owned())
        .collect();
    let code = dispatch(&argv).unwrap_or_else(|fail| match fail {
        Fail::Code(code) => code,
        _ => 1,
    });
    ExitCode::from(u8::try_from(code).unwrap_or(1))
}
