//! Committed defaults and scoped checkpoint handlers.

use crate::args::{parse_cli_args, Args};
use crate::repo::*;
use crate::util::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

pub const FILE: &str = ".spliceconfig";

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Invocation {
    pub command: String,
    pub allowed: String,
    pub cli: Box<Args>,
}

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case", deny_unknown_fields)]
pub(crate) enum Hook {
    Cli,
    Config {
        commit: String,
        file: String,
        scope: String,
        index: usize,
    },
}

#[derive(Default)]
pub struct Configuration {
    files: HashMap<(String, String), Option<String>>,
    entries: HashMap<String, Vec<(String, String)>>,
    executable: HashMap<(String, String), bool>,
}

fn directories(path: &str) -> Vec<String> {
    let mut dirs = vec![String::new()];
    let mut at = String::new();
    for part in path.split('/').filter(|s| !s.is_empty() && *s != ".") {
        if !at.is_empty() {
            at.push('/');
        }
        at.push_str(part);
        dirs.push(at.clone());
    }
    dirs
}

fn option(key: &str, command: &str, allowed: &str) -> Option<String> {
    let key = key.strip_prefix("splice.")?;
    let key = if let Some((section, key)) = key.split_once('.') {
        if section != command {
            return None;
        }
        key
    } else {
        key
    };
    if key == "exec" && matches!(command, "fetch" | "pull" | "push") {
        return Some("--exec".into());
    }
    allowed
        .split_whitespace()
        .chain(["--all"])
        .find(|flag| {
            flag.trim_start_matches('-')
                .replace('-', "")
                .eq_ignore_ascii_case(key)
                || (*flag == "-m" && key == "message")
        })
        .filter(|flag| !matches!(*flag, "--continue-from" | "--rebuilt-commit"))
        .map(str::to_string)
}

fn boolean(value: &str, source: &str) -> Res<bool> {
    match value.to_ascii_lowercase().as_str() {
        "true" | "yes" | "on" | "1" => Ok(true),
        "false" | "no" | "off" | "0" | "" => Ok(false),
        _ => die(format!("{source}: invalid boolean: {value}")),
    }
}

impl Configuration {
    fn source(&mut self, commit: &str, file: &str) -> Option<String> {
        let key = (commit.to_string(), file.to_string());
        self.files
            .entry(key)
            .or_insert_with(|| {
                git(&["rev-parse", "--verify", &format!("{commit}:{file}")])
                    .q()
                    .out()
            })
            .clone()
    }

    pub(crate) fn identity(&mut self, rev: &str, path: &str) -> Vec<Option<String>> {
        let Some(commit) = commit_of(rev) else {
            return Vec::new();
        };
        directories(path)
            .into_iter()
            .map(|scope| {
                let file = if scope.is_empty() {
                    FILE.into()
                } else {
                    format!("{scope}/{FILE}")
                };
                self.source(&commit, &file)
            })
            .collect()
    }

    fn read(&mut self, commit: &str, file: &str) -> Res<Vec<(String, String)>> {
        let key = (commit.to_string(), file.to_string());
        if !self.files.contains_key(&key) {
            let blob = git(&["rev-parse", "--verify", &format!("{commit}:{file}")])
                .q()
                .out();
            self.files.insert(key.clone(), blob);
        }
        let Some(blob) = self.files[&key].as_ref() else {
            return Ok(Vec::new());
        };
        if let Some(entries) = self.entries.get(blob) {
            return Ok(entries.clone());
        }
        let Some(bytes) = git(&[
            "config",
            "--no-includes",
            "--blob",
            blob,
            "--null",
            "--list",
        ])
        .q()
        .bytes() else {
            return die(format!(
                "{file} at {}: invalid Git configuration",
                short(commit)
            ));
        };
        let text = String::from_utf8(bytes).map_err(|_| {
            log_err(format!("{file}: configuration must be UTF-8"));
            Fail::Hard
        })?;
        let entries = text
            .split('\0')
            .filter(|s| !s.is_empty())
            .map(|entry| {
                let (key, value) = entry.split_once('\n').unwrap_or_else(|| {
                    let scalar = matches!(
                        entry.rsplit('.').next().unwrap_or(""),
                        "exec" | "upstream" | "branch" | "messagetemplate" | "message" | "m"
                    );
                    (entry, if scalar { "" } else { "true" })
                });
                (key.to_string(), value.to_string())
            })
            .collect::<Vec<_>>();
        self.entries.insert(blob.clone(), entries.clone());
        Ok(entries)
    }

    pub fn resolve(&mut self, invocation: &Invocation, path: &str) -> Res<Args> {
        let Some(head) = commit_of("HEAD") else {
            return Ok((*invocation.cli).clone());
        };
        let mut values: HashMap<String, String> = HashMap::new();
        for scope in directories(path) {
            let file = if scope.is_empty() {
                FILE.into()
            } else {
                format!("{scope}/{FILE}")
            };
            let entries = self.read(&head, &file)?;
            // A command-specific section wins over the shared section at this scope.
            for specific in [false, true] {
                for (key, value) in &entries {
                    if (key.matches('.').count() > 1) != specific {
                        continue;
                    }
                    if let Some(flag) = option(key, &invocation.command, &invocation.allowed) {
                        if flag != "--exec" {
                            values.insert(flag, value.clone());
                        }
                    }
                }
            }
        }
        let cli = &invocation.cli;
        let value_flags = ["--upstream", "--branch", "--message-template", "-m"];
        let mut defaults = Vec::new();
        let mut ordered: Vec<_> = values.into_iter().collect();
        ordered.sort();
        for (flag, value) in ordered {
            if (!cli.message.is_empty() || !cli.message_template.is_empty())
                && matches!(flag.as_str(), "-m" | "--message-template")
            {
                continue;
            }
            if cli.flags.contains(&flag) {
                continue;
            }
            if value_flags.contains(&flag.as_str()) {
                if !value.is_empty() {
                    defaults.extend([flag, value]);
                }
            } else if boolean(&value, FILE)? {
                defaults.push(flag);
            }
        }
        let mut result = parse_cli_args("", &invocation.allowed, &defaults)?;
        result.paths = cli.paths.clone();
        if !cli.paths.is_empty() {
            result.all = false;
        }
        if cli.all {
            result.all = true;
        }
        if !cli.upstream.is_empty() {
            result.upstream = cli.upstream.clone();
        }
        if !cli.branch.is_empty() {
            result.branch = cli.branch.clone();
        }
        if !cli.message.is_empty() {
            result.message = cli.message.clone();
            result.message_template.clear();
        }
        if !cli.message_template.is_empty() {
            result.message_template = cli.message_template.clone();
            result.message.clear();
        }
        let mut explicit = cli.flags.clone();
        for flag in &cli.flags {
            let alternatives: &[&str] = match flag.as_str() {
                "--bump" | "--rebase" => &["--bump", "--rebase"],
                "--track" | "--no-track" => &["--track", "--no-track"],
                _ => &[],
            };
            explicit.extend(alternatives.iter().map(|s| s.to_string()));
        }
        result.flags.retain(|flag| !explicit.contains(flag));
        result.flags.extend(cli.flags.clone());
        result.exec = cli.exec.clone();
        result.continue_from = cli.continue_from.clone();
        result.rebuilt_commit = cli.rebuilt_commit.clone();
        result.configuration = Some(invocation.clone());
        if cli.message_template.is_empty()
            && cli.message.is_empty()
            && !result.message_template.is_empty()
        {
            crate::message::Template::given(&result.message_template).inspect_err(|_| {
                log_err(format!("{FILE}: invalid messageTemplate"));
            })?;
        }
        result.require_branch_for_track()?;
        Ok(result)
    }

    pub(crate) fn hooks(
        &mut self,
        invocation: &Invocation,
        path: &str,
        views: &[(String, String)],
    ) -> Res<Vec<Hook>> {
        if !invocation.cli.exec.is_empty() {
            return Ok(vec![Hook::Cli]);
        }
        let Some(head) = commit_of("HEAD") else {
            return Ok(Vec::new());
        };
        let mut hooks = Vec::new();
        for scope in directories(path) {
            let mut candidates: Vec<_> = views
                .iter()
                .filter(|(root, _)| scope == *root || scope.starts_with(&format!("{root}/")))
                .collect();
            candidates.sort_by_key(|(root, _)| std::cmp::Reverse(root.len()));
            let mut sources: Vec<(String, String)> = candidates
                .into_iter()
                .map(|(root, commit)| {
                    let relative = scope.strip_prefix(root).unwrap().trim_start_matches('/');
                    let file = if relative.is_empty() {
                        FILE.into()
                    } else {
                        format!("{relative}/{FILE}")
                    };
                    (commit.clone(), file)
                })
                .collect();
            sources.push((
                head.clone(),
                if scope.is_empty() {
                    FILE.into()
                } else {
                    format!("{scope}/{FILE}")
                },
            ));
            let mut selected = None;
            for (commit, file) in sources {
                let entries = self.read(&commit, &file)?;
                if self.files[&(commit.clone(), file.clone())].is_some() {
                    selected = Some((commit, file, entries));
                    break;
                }
            }
            let Some((commit, file, entries)) = selected else {
                continue;
            };
            for specific in [false, true] {
                for (index, (key, value)) in entries.iter().enumerate() {
                    if (key.matches('.').count() > 1) != specific {
                        continue;
                    }
                    if option(key, &invocation.command, &invocation.allowed).as_deref()
                        == Some("--exec")
                    {
                        if value.is_empty() {
                            hooks.clear();
                        } else {
                            hooks.push(Hook::Config {
                                commit: commit.clone(),
                                file: file.clone(),
                                scope: scope.clone(),
                                index,
                            });
                        }
                    }
                }
            }
        }
        Ok(hooks)
    }

    pub(crate) fn command(&mut self, hook: &Hook, cli: &str) -> Res<(String, String)> {
        match hook {
            Hook::Cli => {
                if cli.is_empty() {
                    return die("continuation needs --exec again for its command-line hook");
                }
                Ok((cli.into(), String::new()))
            }
            Hook::Config {
                commit,
                file,
                scope,
                index,
            } => {
                let entries = self.read(commit, file)?;
                let Some((key, value)) = entries.get(*index) else {
                    return die("invalid configured hook continuation");
                };
                if !key.starts_with("splice.") || !key.ends_with(".exec") || value.is_empty() {
                    return die("invalid configured hook continuation");
                }
                Ok((value.clone(), scope.clone()))
            }
        }
    }
}

pub fn initialize(usage: &str, allowed: &str, cli: Args) -> Res<Args> {
    if !cli.continue_from.is_empty() {
        return Ok(cli);
    }
    let command = usage
        .split_whitespace()
        .nth(1)
        .unwrap_or("")
        .strip_prefix("git-splice-")
        .unwrap_or("");
    let invocation = Invocation {
        command: command.into(),
        allowed: allowed.into(),
        cli: Box::new(cli),
    };
    Configuration::default().resolve(&invocation, "")
}

impl Repo<'_> {
    pub(crate) fn configure(&mut self, path: &str) -> Res<()> {
        let Some(invocation) = self.args.configuration.clone() else {
            return Ok(());
        };
        let flags = self.args.flags.clone();
        self.args = self.context.configuration.resolve(&invocation, path)?;
        if matches!(invocation.command.as_str(), "pull" | "merge") && flags != self.args.flags {
            crate::merge::apply_merge_options(self)?;
        }
        if self.context.checkpointing && self.args.has_flag("--rebase") {
            return die("--exec and --continue-from do not support scoped --rebase yet");
        }
        self.message_template_for_scope()?;
        Ok(())
    }
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct ScheduledHook {
    pub hook: Hook,
    pub paths: Vec<String>,
}

impl Configuration {
    pub(crate) fn has_hooks(&mut self, invocation: &Invocation, rev: &str) -> Res<bool> {
        let Some(commit) = commit_of(rev) else {
            return Ok(false);
        };
        let key = (commit.clone(), invocation.command.clone());
        if let Some(found) = self.executable.get(&key) {
            return Ok(*found);
        }
        let files = git(&["ls-tree", "-rz", "--full-tree", "--name-only", &commit])
            .q()
            .bytes()
            .ok_or(Fail::Hard)?;
        for file in nul_fields(&files)
            .into_iter()
            .filter(|p| p == FILE || p.ends_with(&format!("/{FILE}")))
        {
            if self.read(&commit, &file)?.iter().any(|(key, value)| {
                !value.is_empty()
                    && option(key, &invocation.command, &invocation.allowed).as_deref()
                        == Some("--exec")
            }) {
                self.executable.insert(key, true);
                return Ok(true);
            }
        }
        self.executable.insert(key, false);
        Ok(false)
    }
}

pub(crate) fn schedule(
    repo: &mut Repo,
    event: &crate::checkpoint::Event,
) -> Res<Vec<ScheduledHook>> {
    use crate::checkpoint::Event;
    let (paths, views) = match event {
        Event::AfterFetch { fetched } => (
            fetched
                .iter()
                .map(|entry| entry.path.clone())
                .collect::<Vec<_>>(),
            fetched
                .iter()
                .filter(|entry| !entry.failed)
                .filter_map(|entry| {
                    entry
                        .new
                        .as_ref()
                        .map(|commit| (entry.path.clone(), commit.clone()))
                })
                .collect::<Vec<_>>(),
        ),
        Event::AfterMerge { path, .. } => (vec![path.clone()], Vec::new()),
        Event::AfterRebuild(push) | Event::AfterPush(push) => (vec![push.path.clone()], Vec::new()),
        Event::BeforeFold | Event::AfterFold => (repo.selected.clone(), Vec::new()),
    };
    if !repo.args.exec.is_empty() {
        return Ok(vec![ScheduledHook {
            hook: Hook::Cli,
            paths,
        }]);
    }
    let Some(invocation) = repo.args.configuration.clone() else {
        return Ok(Vec::new());
    };
    let mut scheduled: Vec<ScheduledHook> = Vec::new();
    for path in paths {
        for hook in repo
            .context
            .configuration
            .hooks(&invocation, &path, &views)?
        {
            if let Some(existing) = scheduled.iter_mut().find(|item| item.hook == hook) {
                if !existing.paths.contains(&path) {
                    existing.paths.push(path.clone());
                }
            } else {
                scheduled.push(ScheduledHook {
                    hook,
                    paths: vec![path.clone()],
                });
            }
        }
    }
    scheduled.sort_by_key(|item| match &item.hook {
        Hook::Cli => 0,
        Hook::Config { scope, .. } => scope.split('/').filter(|p| !p.is_empty()).count(),
    });
    Ok(scheduled)
}

pub(crate) fn use_checkpoints(
    context: &mut crate::context::ExecutionContext,
    args: &Args,
) -> Res<bool> {
    if !args.has_flag("--rebase") || !args.exec.is_empty() || !args.continue_from.is_empty() {
        return Ok(true);
    }
    match &args.configuration {
        Some(invocation) => context.configuration.has_hooks(invocation, "HEAD"),
        None => Ok(false),
    }
}
