//! The check-drawing command: see the library, lib.rs, for what it checks.

use check_drawing::check::{Checker, Labels};
use check_drawing::{labels, placement, tree};
use std::process::ExitCode;

const USAGE: &str = "usage: check-drawing <drawing> [--alias <name>=<term>...] [<label>=<rev>...]\n       check-drawing tree [--mark pulled|carried]... [<label>=<rev>...]\n       check-drawing labels <page>...\n       check-drawing placement <page>...";

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
    let mut marks = tree::Marks::default();
    let mut rest = rest.iter();
    while let Some(arg) = rest.next() {
        if drawing == "tree" && arg == "--mark" {
            match rest.next().map(String::as_str) {
                Some("pulled") => marks.pulled = true,
                Some("carried") => marks.carried = true,
                _ => {
                    eprintln!("{USAGE}");
                    return ExitCode::FAILURE;
                }
            }
        } else if arg == "--alias" {
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
    let ok = if drawing == "tree" {
        tree::generate(&labels, &marks)
    } else {
        Checker::run(drawing, &labels)
    };
    if ok {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}
