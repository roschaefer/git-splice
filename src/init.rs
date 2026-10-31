//! git splice init.

use crate::args::parse_args;
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
                    .input(format!(
                        "{refs}
"
                    ))
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
    let content = git(&["cat-file", "blob", &blob])
        .bytes()
        .ok_or(Fail::Hard)?;
    if std::fs::write(&state_file, content).is_err() {
        return die(format!("{state_file}: can't write it"));
    }
    // -f: an ignore rule matching .splice mustn't stop it, it's committed by
    // definition.
    if git(&["add", "-f", "--", &state_file]).run() != 0 {
        return Err(Fail::Hard);
    }
    let message = repo.commit_message(format!("splice: init {path}"));
    if git(&["commit", "--quiet", "-m", &message, "--", &state_file]).run() != 0 {
        return Err(Fail::Hard);
    }
    log_ok(format!(
        "{path}: initialized -- 'git splice push {}' publishes it",
        shell_quote(&path)
    ));
    Ok(0)
}
