//! git splice key.

use crate::args::parse_args;
use crate::repo::*;
use crate::util::*;

pub const USAGE: &str = include_str!("usage/key.txt");

/// Renames upstream key <old> to <new>: its refs, in one transaction, then its
/// entry in the repository's config. Under the lock that recording a key takes,
/// so neither picks a key the other is taking.
fn rename_upstream_key(repo: &mut Repo, old: &str, new: &str) -> Res<()> {
    if !valid_upstream_key(new) {
        return die(format!(
            "'{new}' isn't a valid key -- use lower-case letters, digits, '.', '_' and '-', at most 64, starting and ending with a letter or digit"
        ));
    }
    let _lock = repo.lock_upstream_keys()?;
    repo.reread_upstream_keys()?;
    // Another command may have renamed it since this one read the config.
    if repo.url_for_key(old).is_none() {
        return die(format!("key '{old}' is gone -- run 'git splice key' again"));
    }
    if repo.key_taken(new)? {
        return die(format!(
            "key '{new}' is taken -- 'git config --local --get-regexp ^splice\\.' lists the keys"
        ));
    }
    let Some(refs) = git(&[
        "for-each-ref",
        "--format=%(refname) %(objectname)",
        &format!("refs/splices/{old}/"),
    ])
    .out() else {
        return die(format!("couldn't move the refs of key '{old}'"));
    };
    let mut moves = String::new();
    for line in refs.lines() {
        if let Some((reference, object)) = line.split_once(' ') {
            let rest = reference
                .strip_prefix(&format!("refs/splices/{old}/"))
                .unwrap_or(reference);
            moves.push_str(&format!("create refs/splices/{new}/{rest} {object}\n"));
            moves.push_str(&format!("delete {reference} {object}\n"));
        }
    }
    if !git(&["update-ref", "--stdin"]).input(moves).ok() {
        return die(format!("couldn't move the refs of key '{old}'"));
    }
    if !git(&[
        "config",
        "--local",
        "--rename-section",
        &format!("splice.{old}"),
        &format!("splice.{new}"),
    ])
    .ok()
    {
        return die(format!(
            "moved the refs to refs/splices/{new}/, but couldn't rename splice.{old} in the repository's config -- rename it by hand (git config --local --rename-section splice.{old} splice.{new})"
        ));
    }
    // In every upstream branch tracked on a monorepo branch.
    let tracked = git(&["config", "--local", "--get-regexp", r"^branch\..*\.splice$"])
        .q()
        .out()
        .unwrap_or_default();
    for line in tracked.lines() {
        let Some((name, value)) = line.split_once(' ') else {
            continue;
        };
        let Some(branch) = value.strip_prefix(&format!("{old}:")) else {
            continue;
        };
        let renamed = format!("{new}:{branch}");
        if !git(&[
            "config",
            "--local",
            "--fixed-value",
            "--replace-all",
            name,
            &renamed,
            value,
        ])
        .ok()
        {
            return die(format!(
                "couldn't rename key '{old}' in {name} -- rename it by hand (git config --local --fixed-value --replace-all {name} {} {})",
                shell_quote(&renamed),
                shell_quote(value)
            ));
        }
    }
    Ok(())
}

pub fn run(argv: &[String]) -> Res<i32> {
    let args = parse_args(USAGE, "--upstream", argv)?;
    args.require(USAGE, "key", 1, 2)?;
    let path = normalize_path(&args.paths[0]);
    let new = args.paths.get(1).cloned().unwrap_or_default();
    let upstream = args.upstream.clone();
    let mut repo = Repo::new(args);
    repo.open()?;
    repo.require_splice(&path)?;
    repo.use_upstreams(&upstream, std::slice::from_ref(&path))?;
    let key = repo.key_of(&path);
    if key.is_empty() {
        return die(format!(
            "{path}: its upstream has no key yet -- 'git splice fetch {}' records one",
            shell_quote(&path)
        ));
    }
    if new.is_empty() {
        say(&key);
    } else if new == key {
        log_ok(format!("{path}: key is '{key}' already"));
    } else {
        rename_upstream_key(&mut repo, &key, &new)?;
        log_ok(format!("{path}: renamed key '{key}' to '{new}'"));
    }
    Ok(0)
}
