//! check-drawing: checks a draw.io drawing of commit graphs against the
//! repositories it shows. See README.md next to src/ for the drawing's
//! vocabulary and its limits.
//!
//! What it reads about a splice, its boundary, rebuild, keys and the folders
//! it had, comes from git-splice's own code, so a drawing is checked against
//! what the tool really does.

mod check;
mod diagram;
mod history;
mod labels;
mod placement;

use check::{Checker, Labels};
use std::process::ExitCode;

const USAGE: &str = "usage: check-drawing <drawing> [--alias <name>=<term>...] [<label>=<rev>...]\n       check-drawing labels <page>...\n       check-drawing placement <page>...";

/// <name>=<value>, split at the first `=`; without one, both are the whole.
fn split_pair(pair: &str) -> (String, String) {
    match pair.split_once('=') {
        Some((name, value)) => (name.to_string(), value.to_string()),
        None => (pair.to_string(), pair.to_string()),
    }
}

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let Some((drawing, rest)) = argv.split_first() else {
        eprintln!("{USAGE}");
        return ExitCode::FAILURE;
    };
    if drawing == "placement" {
        return if placement::run(rest) {
            ExitCode::SUCCESS
        } else {
            ExitCode::FAILURE
        };
    }
    if drawing == "labels" {
        return if labels::run(rest) {
            ExitCode::SUCCESS
        } else {
            ExitCode::FAILURE
        };
    }
    let mut labels = Labels::default();
    let mut rest = rest.iter();
    while let Some(arg) = rest.next() {
        if arg == "--alias" {
            let Some(alias) = rest.next() else {
                eprintln!("{USAGE}");
                return ExitCode::FAILURE;
            };
            let (name, term) = split_pair(alias);
            labels.aliases.insert(name, term);
        } else {
            let (label, rev) = split_pair(arg);
            labels.revs.insert(label, rev);
        }
    }
    if Checker::run(drawing, &labels) {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}
