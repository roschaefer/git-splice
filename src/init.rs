//! git splice init.

use crate::args::parse_args;
use crate::message::Message;
use crate::repo::*;
use crate::state::*;
use crate::util::*;

pub const USAGE: &str = include_str!("usage/init.txt");

/// The branch the HEAD of empty repository <url> names, e.g. "master".
/// ls-remote shows nothing for an empty repository, but a clone learns its
/// unborn HEAD -- and there is nothing to download.
fn empty_upstream_default_branch(url: &str) -> String {
    let folder = Temp::new();
    let probe = folder.str();
    if !git(&["clone", "--quiet", "--bare", "--no-tags", "--", url, &probe])
        .q()
        .ok()
    {
        return String::new();
    }
    git(&["-C", &probe, "symbolic-ref", "--quiet", "--short", "HEAD"])
        .q()
        .out()
        .unwrap_or_default()
}

pub fn run(argv: &[String]) -> Res<i32> {
    let args = parse_args(USAGE, "-m", argv)?;
    args.require(USAGE, "init", 2, 2)?;
    if args.paths[0].is_empty() || args.paths[1].is_empty() {
        eprint_text(USAGE);
        return Ok(1);
    }
    let path = normalize_path(&args.paths[0]);
    let url = args.paths[1].clone();
    require_usable_splice_path(&path, "rename the folder")?;

    let mut repo = Repo::new(args);
    repo.open()?;
    repo.require_message_template(Message {
        command: "init",
        ..Message::default()
    })?;
    current_branch()?;
    require_no_splice_in_progress()?;
    if repo.is_splice_path(&path) {
        return die(format!("{path} is a splice already"));
    }
    if folder_tree("HEAD", &path).is_none() {
        return die(format!(
            "{path}: no committed folder here -- to splice in an existing repository, use 'git splice clone'"
        ));
    }
    let state_file = format!("{path}/{STATE_FILE}");
    if std::fs::symlink_metadata(&state_file).is_ok() {
        return die(format!(
            "{state_file} exists, but isn't committed -- remove it or commit it"
        ));
    }
    let Some(heads) = git(&["ls-remote", "--heads", "--", &url]).out() else {
        return die(format!("{path}: can't reach {url}"));
    };
    if !heads.is_empty() {
        return die(format!(
            "{url} has commits already -- to combine them with {path}, use 'git splice clone --merge {} {}'",
            shell_quote(&url),
            shell_quote(&path)
        ));
    }

    // Map the monorepo's default branch to the upstream's, as clone does. An
    // empty repository has no branch yet, but its HEAD still names one.
    let upstream_default = empty_upstream_default_branch(&url);
    let monorepo_default = repo.monorepo_default_branch();
    let container_default = repo.container_default_branch(&path)?;
    let mut default_branch = String::new();
    if !upstream_default.is_empty() {
        if monorepo_default.is_empty() && upstream_default != current_branch()? {
            return die(format!(
                "{path}: upstream's default branch is '{upstream_default}', and the monorepo's can't be determined -- set it (git config init.defaultBranch <branch>, or git remote set-head origin --auto) and re-run"
            ));
        }
        if !container_default.is_empty() && upstream_default != container_default {
            default_branch = upstream_default;
        }
    }

    // The splices directly inside follow the new splice's default branch from
    // now on. Each upstream of theirs that followed another one records it, so
    // it keeps following that.
    let new_default = if default_branch.is_empty() {
        container_default.clone()
    } else {
        default_branch.clone()
    };
    let prefix = format!("{path}/");
    let inside: Vec<String> = repo
        .all_paths
        .iter()
        .filter(|inner| {
            inner.starts_with(&prefix)
                && splice_above_in("HEAD", inner).is_none_or(|above| !above.starts_with(&prefix))
        })
        .cloned()
        .collect();
    let mut kept: Vec<(String, String, String)> = Vec::new();
    for inner in &inside {
        repo.require_upstream_list(inner)?;
        let followed = repo.container_default_branch(inner)?;
        if followed.is_empty() || followed == new_default {
            continue;
        }
        for name in repo.upstream_lists[inner].clone() {
            if upstream_config(inner, &name, "default-branch").is_empty()
                && upstream_config(inner, &name, "default-pin").is_empty()
            {
                kept.push((inner.clone(), name, followed.clone()));
            }
        }
    }
    // The upstream is empty, so refs fetched from it before name branches it
    // no longer has.
    let key = repo.upstream_key(&url)?;
    if !key.is_empty() {
        let refs = git(&[
            "for-each-ref",
            "--format=delete %(refname)",
            &format!("refs/splices/{key}/"),
        ])
        .out();
        let removed = refs.is_some_and(|refs| {
            refs.is_empty()
                || git(&["update-ref", "--stdin"])
                    .input(format!("{refs}\n"))
                    .ok()
        });
        if !removed {
            return die(format!(
                "{path}: couldn't remove the refs fetched from {url} before"
            ));
        }
    }
    let id = new_splice_id(&path, &url, "");
    let url_key = format!("upstream.{DEFAULT_UPSTREAM}.url");
    let branch_key = format!("upstream.{DEFAULT_UPSTREAM}.default-branch");
    let blob = state_blob(
        &path,
        &[
            ("id", &id),
            (&url_key, &url),
            (&branch_key, &default_branch),
        ],
    )
    .map_err(|_| Fail::Hard)?;
    let mut files = vec![(state_file.clone(), blob)];
    for inner in &inside {
        let keys: Vec<(String, &str)> = kept
            .iter()
            .filter(|(path, _, _)| path == inner)
            .map(|(_, name, branch)| (format!("upstream.{name}.default-branch"), branch.as_str()))
            .collect();
        if keys.is_empty() {
            continue;
        }
        let settings: Vec<(&str, &str)> = keys
            .iter()
            .map(|(key, branch)| (key.as_str(), *branch))
            .collect();
        let blob = state_blob_in(inner, "HEAD", &settings).map_err(|_| Fail::Hard)?;
        files.push((format!("{inner}/{STATE_FILE}"), blob));
    }
    let message = repo.commit_message(
        format!("splice: init {path}"),
        Message {
            command: "init",
            path: &path,
            ..Message::default()
        },
    )?;
    if commit_state_files(&files, &message).is_err() {
        return fail(format!("{path}: init failed"));
    }
    log_ok(format!(
        "{path}: initialized -- 'git splice push {}' publishes it",
        shell_quote(&path)
    ));
    for (inner, name, branch) in &kept {
        log_ok(format!(
            "{inner}: records default-branch '{branch}' for {name}, which it followed before"
        ));
    }
    Ok(0)
}
