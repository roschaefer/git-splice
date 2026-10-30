//! Parsing the arguments every command shares.

use crate::util::*;

#[derive(Default, Clone)]
pub struct Args {
    pub all: bool,
    pub upstream: String,
    pub rebuilt_commit: String,
    pub branch: String,
    pub message: String,
    pub paths: Vec<String>,
    pub flags: Vec<String>,
}

impl Args {
    pub fn has_flag(&self, flag: &str) -> bool {
        self.flags.iter().any(|f| f == flag)
    }

    /// Ends the command unless it got no --all and from <min> to <max> paths;
    /// with the wrong number, after printing how to call it.
    pub fn require(&self, usage: &str, command: &str, min: usize, max: usize) -> Res<()> {
        if self.all {
            return die(format!("{command} takes no --all"));
        }
        if self.paths.len() < min || self.paths.len() > max {
            eprint_text(usage);
            return Err(Fail::Hard);
        }
        Ok(())
    }

    /// -m names one splice's commit.
    pub fn require_one_splice_for_message(&self) -> Res<()> {
        if !self.message.is_empty() && (self.all || self.paths.len() > 1) {
            return die("-m names one splice's commit -- name one path, not several or --all");
        }
        Ok(())
    }

    /// --track tracks the branch --branch names.
    pub fn require_branch_for_track(&self) -> Res<()> {
        if self.has_flag("--track") && self.has_flag("--no-track") {
            return die("--track and --no-track contradict each other -- give one");
        }
        if self.has_flag("--track") && self.branch.is_empty() {
            return die("--track tracks the branch --branch names -- add --branch <name>");
        }
        Ok(())
    }
}

/// Parses the arguments of a command. <allowed> names the options it takes,
/// e.g. "--merge -m". -h and --help print <usage> and end the command.
/// Everything after `--` is a path.
pub fn parse_args(usage: &str, allowed: &str, argv: &[String]) -> Res<Args> {
    let allowed: Vec<&str> = allowed.split_whitespace().collect();
    let refuse = |option: &str| -> Res<()> {
        if allowed.contains(&option) {
            return Ok(());
        }
        eprint_text(usage);
        die(format!("unknown option: {option}"))
    };
    let mut args = Args::default();
    let mut i = 0;
    while i < argv.len() {
        let arg = argv[i].as_str();
        match arg {
            "-h" | "--help" => {
                say(usage.trim_end_matches('\n'));
                std::process::exit(0);
            }
            "--all" => args.all = true,
            "--" => {
                args.paths.extend_from_slice(&argv[i + 1..]);
                break;
            }
            _ if ["--upstream", "--rebuilt-commit", "--branch"]
                .iter()
                .any(|o| arg == *o || arg.starts_with(&format!("{o}="))) =>
            {
                let option = arg.split('=').next().unwrap_or(arg);
                refuse(option)?;
                let value = if let Some((_, value)) = arg.split_once('=') {
                    value.to_string()
                } else {
                    i += 1;
                    argv.get(i).cloned().unwrap_or_default()
                };
                match option {
                    "--upstream" => {
                        if value.is_empty() {
                            return die("--upstream needs an upstream's name");
                        }
                        args.upstream = value;
                    }
                    "--rebuilt-commit" => {
                        if value.is_empty() {
                            return die("--rebuilt-commit needs a commit");
                        }
                        args.rebuilt_commit = value;
                    }
                    _ => {
                        if value.is_empty() {
                            return die("--branch needs an upstream branch's name");
                        }
                        args.branch = value;
                    }
                }
            }
            _ if arg == "-m"
                || arg == "--message"
                || arg.starts_with("--message=")
                || (arg.starts_with("-m") && !arg.starts_with("--")) =>
            {
                if !allowed.contains(&"-m") {
                    eprint_text(usage);
                    return die(format!(
                        "unknown option: {}",
                        arg.split('=').next().unwrap_or(arg)
                    ));
                }
                let value = if let Some(value) = arg.strip_prefix("--message=") {
                    value.to_string()
                } else if arg.len() > 2 && !arg.starts_with("--") {
                    arg[2..].to_string()
                } else {
                    i += 1;
                    argv.get(i).cloned().unwrap_or_default()
                };
                if value.is_empty() {
                    return die("-m needs a message");
                }
                if args.message.is_empty() {
                    args.message = value;
                } else {
                    args.message = format!("{}\n\n{value}", args.message);
                }
            }
            _ if arg.starts_with('-') => {
                refuse(arg)?;
                args.flags.push(arg.to_string());
            }
            _ => args.paths.push(arg.to_string()),
        }
        i += 1;
    }
    Ok(args)
}
