//! git splice -- during the port from bash (#203), commands not ported yet
//! run the bash entrypoint next to this crate's manifest. Until the last
//! one is ported, releases ship the bash entrypoint, not this binary.

use std::env;
use std::os::unix::process::CommandExt;
use std::process::{Command, ExitCode};

const BASH_ENTRYPOINT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/git-splice");

fn main() -> ExitCode {
    let args: Vec<_> = env::args_os().skip(1).collect();
    if args.first().is_some_and(|arg| arg == "--version") {
        println!("git splice version {}", env!("CARGO_PKG_VERSION"));
        return ExitCode::SUCCESS;
    }
    let error = Command::new(BASH_ENTRYPOINT).args(args).exec();
    eprintln!("!!   can't run {BASH_ENTRYPOINT}: {error}");
    ExitCode::FAILURE
}
