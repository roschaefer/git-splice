//! git splice clone.

use crate::args::parse_args;
use crate::fetch::{fetch_by_id, fetch_upstream};
use crate::repo::*;
use crate::state::*;
use crate::util::*;
use std::path::Path;
use std::process::Command;

pub const USAGE: &str = include_str!("usage/clone.txt");

/// The attributes that change what a checkout writes, or what git add stores.
const CHECKOUT_ATTRIBUTES: [&str; 5] = ["text", "eol", "filter", "ident", "working-tree-encoding"];

/// The folder name `git clone` would pick for <url>.
fn default_clone_path(url: &str) -> String {
    let name = url.strip_suffix('/').unwrap_or(url);
    let name = name.strip_suffix(".git").unwrap_or(name);
    let name = name.rsplit('/').next().unwrap_or(name);
    name.rsplit(':').next().unwrap_or(name).to_string()
}

/// The mode of <path> in commit <rev>, e.g. 160000 for a submodule, or nothing
/// if it isn't there.
fn path_mode(rev: &str, path: &str) -> String {
    let entry = git(&["ls-tree", "-z", rev, "--", path])
        .bytes()
        .unwrap_or_default();
    let entry = text(&entry).replace('\0', "");
    match entry.split_once('\t') {
        Some((fields, name)) if name == path => fields.split(' ').next().unwrap_or("").to_string(),
        _ => String::new(),
    }
}

/// The path of the first submodule in upstream commit <commit>, if any. A
/// splice can't carry one: the upstream's .gitmodules would sit in the folder,
/// where Git doesn't read it, so nobody could check it out.
fn upstream_submodule(commit: &str) -> Option<String> {
    let listing = git(&["ls-tree", "-r", commit]).out().unwrap_or_default();
    listing.lines().find_map(|line| {
        let (fields, file) = line.split_once('\t')?;
        fields.starts_with("160000 ").then(|| file.to_string())
    })
}

/// What fetching a new upstream found out.
#[derive(Default)]
struct NewUpstream {
    default_branch: String,
    upstream_default: String,
    monorepo_default: String,
    container_default: String,
}

/// Prints the git output of a fetch and fails if it failed.
fn fetch_new(url: &str, prefix: &str, path: &str) -> Res<()> {
    let (ok, output) = fetch_upstream(url, prefix, &[]);
    if !output.is_empty() {
        eprint_text(&format!("{output}\n"));
    }
    if !ok {
        return die(format!("{path}: fetch failed"));
    }
    Ok(())
}

impl Repo {
    /// Fetches <url>, a new upstream of a splice to be created at <path>, and
    /// registers it as that splice's default upstream.
    fn register_new_upstream(&mut self, path: &str, url: &str) -> Res<()> {
        self.create_upstream_key(url)?;
        self.upstream_lists
            .insert(path.to_string(), vec![DEFAULT_UPSTREAM.to_string()]);
        self.upstream_urls.insert(
            (path.to_string(), DEFAULT_UPSTREAM.to_string()),
            url.to_string(),
        );
        self.default_upstreams
            .insert(path.to_string(), DEFAULT_UPSTREAM.to_string());
        self.use_upstream(path, DEFAULT_UPSTREAM)?;
        log_step(format!("{path}: fetching {url}"));
        fetch_new(url, &self.refs_prefix(path), path)
    }

    /// As register_new_upstream, and works out the default-branch .splice has
    /// to record: the upstream's default branch where it's named differently
    /// from the default branch of what the splice lives in, else nothing.
    fn fetch_new_upstream(&mut self, path: &str, url: &str) -> Res<NewUpstream> {
        // Before the fetch: refuses if the splice above leaves it open.
        self.container_default_branch(path)?;
        self.register_new_upstream(path, url)?;
        if !self.splice_fetched(path) {
            return die(format!(
                "{url} has no branches yet -- to publish {path} there, use 'git splice init {} {}'",
                shell_quote(path),
                shell_quote(url)
            ));
        }
        // Map the monorepo's default branch to the upstream's, if it differs
        // from the default branch of what the splice lives in.
        let symref = git(&["ls-remote", "--symref", "--", url, "HEAD"])
            .q()
            .out_anyway();
        let upstream_default = symref
            .lines()
            .find_map(|line| {
                line.strip_prefix("ref: refs/heads/")?
                    .strip_suffix("\tHEAD")
                    .map(str::to_string)
            })
            .unwrap_or_default();
        let mut found = NewUpstream {
            monorepo_default: self.monorepo_default_branch(),
            container_default: self.container_default_branch(path)?,
            upstream_default,
            ..NewUpstream::default()
        };
        if !found.upstream_default.is_empty() {
            if found.monorepo_default.is_empty() && found.upstream_default != current_branch()? {
                // Without the monorepo's default branch, the splice couldn't
                // map it to upstream's: it would look for the current branch
                // upstream from the start.
                return die(format!(
                    "{path}: upstream's default branch is '{}', and the monorepo's can't be determined -- set it (git config init.defaultBranch <branch>, or git remote set-head origin --auto) and re-run",
                    found.upstream_default
                ));
            }
            if !found.container_default.is_empty()
                && found.upstream_default != found.container_default
            {
                found.default_branch = found.upstream_default.clone();
            }
        }
        Ok(found)
    }

    /// What the splice at <path> of submodule <name>, committed at <commit>,
    /// records to mean what the submodule meant: (default-branch, default-pin,
    /// what's pinned, for the message). Its branch setting names the branch it
    /// follows: that one, unless the splice would follow it anyway; "." follows
    /// the branch named like the current one, which a splice does without a
    /// default-branch. Without a branch, the submodule stayed at its commit, and
    /// so does the splice. Inside a splice that pins a tag or a commit, there's
    /// no such branch: "." stays at its commit too.
    fn submodule_defaults(
        &mut self,
        path: &str,
        gitmodules: &str,
        name: &str,
        commit: &str,
    ) -> Res<(String, String, String)> {
        let branch = git(&[
            "config",
            "--blob",
            &format!("HEAD:{gitmodules}"),
            &format!("submodule.{name}.branch"),
        ])
        .q()
        .out()
        .unwrap_or_default();
        let mut default_branch = String::new();
        let mut pin = String::new();
        let mut pinned_as = "the submodule was".to_string();
        let above = splice_above_in("HEAD", path);
        let mut pinned_above = false;
        if let Some(above) = &above {
            pinned_above = self.resolve_default_target(above, None)?.kind != TargetKind::Branch;
        }
        match branch.as_str() {
            "" => pin = commit.to_string(),
            "." => {
                if pinned_above {
                    pin = commit.to_string();
                    pinned_as = format!("{} is", above.unwrap_or_default());
                }
            }
            _ => {
                if pinned_above || branch != self.container_default_branch(path)? {
                    default_branch = branch;
                }
            }
        }
        if self.monorepo_default_branch().is_empty() {
            if !pin.is_empty() {
                return die(format!(
                    "{path}: the submodule stays at {}, and a pin applies on the monorepo's default branch, which can't be determined -- set it (git config init.defaultBranch <branch>, or git remote set-head origin --auto) and re-run",
                    short(commit)
                ));
            }
            if !default_branch.is_empty() {
                return die(format!(
                    "{path}: the submodule follows '{default_branch}', and a default-branch applies on the monorepo's default branch, which can't be determined -- set it (git config init.defaultBranch <branch>, or git remote set-head origin --auto) and re-run"
                ));
            }
        }
        Ok((default_branch, pin, pinned_as))
    }
}

/// The name of the submodule at <path>, relative to the folder of .gitmodules
/// file <gitmodules> in HEAD.
fn submodule_name(gitmodules: &str, path: &str) -> Option<String> {
    let listing = git(&[
        "config",
        "-z",
        "--blob",
        &format!("HEAD:{gitmodules}"),
        "--get-regexp",
        r"^submodule\..*\.path$",
    ])
    .q()
    .bytes()?;
    nul_fields(&listing).iter().find_map(|entry| {
        let (key, value) = entry.split_once('\n')?;
        if normalize_path(value) != path {
            return None;
        }
        let key = key.strip_prefix("submodule.")?;
        key.strip_suffix(".path").map(str::to_string)
    })
}

/// Submodule URL <url> as `git submodule` reads it: a relative one, starting
/// with ./ or ../, is relative to URL <base>, if given: the upstream of the
/// splice the submodule is in. Else it's relative to the URL of the monorepo's
/// default remote -- the current branch's remote, else origin -- or, without
/// one, to the monorepo itself. Git resolves it: `git submodule init` in a
/// throwaway repository whose origin has that URL records it resolved.
fn resolve_submodule_url(url: &str, base: &str) -> Res<String> {
    if !url.starts_with("./") && !url.starts_with("../") {
        return Ok(url.to_string());
    }
    let toplevel = || {
        git(&["rev-parse", "--show-toplevel"])
            .out()
            .unwrap_or_default()
    };
    let mut base = base.to_string();
    if base.is_empty() {
        let branch = git(&["symbolic-ref", "--quiet", "--short", "HEAD"])
            .out()
            .unwrap_or_default();
        let remote = git(&["config", &format!("branch.{branch}.remote")])
            .q()
            .out()
            .unwrap_or_else(|| "origin".to_string());
        base = git(&["config", &format!("remote.{remote}.url")])
            .q()
            .out()
            .unwrap_or_else(toplevel);
    }
    // A relative path is relative to the monorepo, not to the throwaway
    // repository.
    if !base.starts_with('/') && !base.contains(':') {
        base = format!("{}/{base}", toplevel());
    }
    let folder = Temp::new();
    let resolved = (|| {
        std::fs::create_dir(&folder.path).ok()?;
        let dir = folder.str();
        let in_dir = |args: &[&str]| {
            let mut all = vec!["-C", &dir];
            all.extend_from_slice(args);
            git(&all)
        };
        let empty = git(&["hash-object", "-t", "tree", "/dev/null"]).out()?;
        let entry = format!("160000,{empty},s");
        (in_dir(&["init", "-q"]).ok()
            && in_dir(&["config", "remote.origin.url", &base]).ok()
            && in_dir(&["config", "--file", ".gitmodules", "submodule.s.path", "s"]).ok()
            && in_dir(&["config", "--file", ".gitmodules", "submodule.s.url", url]).ok()
            && in_dir(&["update-index", "--add", "--cacheinfo", &entry]).ok()
            && in_dir(&["submodule", "--quiet", "init", "--", "s"]).ok())
        .then(|| in_dir(&["config", "submodule.s.url"]).out())?
    })();
    match resolved {
        Some(resolved) if !resolved.is_empty() => Ok(resolved),
        _ => die(format!(
            "can't resolve submodule URL '{url}' against '{base}'"
        )),
    }
}

/// Ends the command if a step of a conversion failed: git said why, and what's
/// left to do would only build on it.
fn must(code: i32) -> Res<()> {
    if code == 0 {
        Ok(())
    } else {
        Err(Fail::Hard)
    }
}

fn exists_or_link(path: &str) -> bool {
    std::fs::symlink_metadata(path).is_ok()
}

/// Ends the command unless converting the submodule at <path>, committed at
/// <commit>, can't lose anything. The conversion writes to the index, .gitmodules
/// file <gitmodules>, the folder and its .splice, and each must be unchanged
/// from HEAD or missing. Content is compared, not just what git status says:
/// index flags like assume-unchanged hide edits from it.
fn refuse_lossy_submodule_conversion(path: &str, commit: &str, gitmodules: &str) -> Res<()> {
    if !git(&["diff", "--cached", "--quiet"]).ok() {
        return die(format!(
            "{path}: there are staged changes -- commit or unstage them first, the conversion commits only its own"
        ));
    }
    // HEAD has a .gitmodules: it names the submodule.
    if !exists_or_link(gitmodules)
        || git(&["hash-object", "--", gitmodules]).out()
            != git(&["rev-parse", &format!("HEAD:{gitmodules}")]).out()
    {
        return die(format!(
            "{path}: {gitmodules} has uncommitted changes -- commit or discard them first"
        ));
    }
    let mut parent = path;
    while let Some((above, _)) = parent.rsplit_once('/') {
        parent = above;
        if std::fs::symlink_metadata(parent).is_ok_and(|meta| meta.file_type().is_symlink()) {
            return die(format!(
                "{path}: {parent} is a symbolic link -- the submodule's folder must be inside the repository"
            ));
        }
    }
    let state_file = format!("{path}/{STATE_FILE}");
    let dot_git = format!("{path}/.git");
    let folder = Path::new(path);
    if std::fs::symlink_metadata(path).is_ok_and(|meta| meta.file_type().is_symlink()) {
        return die(format!(
            "{path}: a symbolic link takes the submodule's place -- remove it first"
        ));
    } else if Path::new(&dot_git).exists() {
        if git(&["-C", path, "rev-parse", "HEAD"]).q().out().as_deref() != Some(commit) {
            let at = short(commit);
            return die(format!(
                "{path}: the submodule's checkout isn't at {at}, the commit in HEAD -- commit the submodule's new commit, or check out {at} in it"
            ));
        }
        let status = git(&["-C", path, "status", "--porcelain", "--untracked-files=all"])
            .out()
            .unwrap_or_default();
        if !status.is_empty() {
            return die(format!(
                "{path}: the submodule's checkout has changes -- commit and push them, or discard them, first"
            ));
        }
        // An ignored one: status doesn't show it.
        if exists_or_link(&state_file) {
            return die(format!(
                "{state_file} exists in the submodule's checkout -- move it away first"
            ));
        }
    } else if folder.exists() && !folder.is_dir() {
        return die(format!(
            "{path}: a file takes the place of the uninitialized submodule -- move it away first"
        ));
    } else if folder.is_dir()
        && std::fs::read_dir(folder).is_ok_and(|mut entries| entries.next().is_some())
    {
        return die(format!(
            "{path}: the folder of the uninitialized submodule isn't empty -- move its files away first"
        ));
    }
    Ok(())
}

/// The name of a tag of upstream <url> that names <commit>, if any.
fn tag_naming(url: &str, commit: &str) -> Option<String> {
    let tags = git(&["ls-remote", "--tags", "--", url]).q().out()?;
    tags.lines().find_map(|line| {
        let (id, name) = line.split_once('\t')?;
        if id != commit {
            return None;
        }
        let name = name.strip_prefix("refs/tags/").unwrap_or(name);
        Some(name.strip_suffix("^{}").unwrap_or(name).to_string())
    })
}

/// A .gitattributes pattern for everything below folder <path>: a leading #, !
/// or " would make a comment, a negative pattern or a quoted one.
fn attributes_pattern(path: &str) -> String {
    if path.starts_with(['#', '!', '"']) {
        format!("\\{path}/**")
    } else {
        format!("{path}/**")
    }
}

/// The checkout attributes tree <tree> gives files <names> (NUL-separated),
/// each with <prefix> in front, as one "<attribute> <value>" line each, without
/// the path: the same files in another folder compare equal. Reads only <tree>'s
/// .gitattributes, from the top, as checkout and git add do. Git warns about a
/// macro defined below the top each time it reads one; the caller says what
/// that means instead.
fn checkout_attributes(tree: &str, prefix: &str, names: &[u8]) -> Option<Vec<String>> {
    let mut input = Vec::new();
    for name in names.split(|&b| b == 0).filter(|name| !name.is_empty()) {
        input.extend_from_slice(prefix.as_bytes());
        input.extend_from_slice(name);
        input.push(0);
    }
    let mut args = vec!["check-attr", "-z", "--stdin"];
    let source = format!("--source={tree}");
    args.push(&source);
    args.extend_from_slice(&CHECKOUT_ATTRIBUTES);
    let output = git(&args).q().input(input).bytes()?;
    let fields = nul_fields(&output);
    Some(
        fields
            .chunks_exact(3)
            .map(|record| format!("{} {}", record[1], record[2]))
            .collect(),
    )
}

/// Tree <tree> with file <file> replaced by blob <blob>, in the file's mode.
fn tree_with_blob(tree: &str, file: &str, blob: &str) -> Option<String> {
    let listing = git(&["ls-tree", tree, "--", file])
        .out()
        .unwrap_or_default();
    let mode = listing.split(' ').next().filter(|mode| !mode.is_empty());
    let mode = mode.unwrap_or("100644");
    let index = Temp::new();
    let indexed = |args: &[&str]| git(args).env("GIT_INDEX_FILE", &index.path);
    let entry = format!("{mode},{blob},{file}");
    (indexed(&["read-tree", tree]).ok() && indexed(&["update-index", "--cacheinfo", &entry]).ok())
        .then(|| indexed(&["write-tree"]).out())?
}

/// Ends the command where Git would apply other checkout attributes to the files
/// of a new splice at <path>, at upstream commit <commit>, in monorepo tree
/// <tree>, than in upstream, where only upstream's own .gitattributes count.
/// Names the line that unsets them for the folder in the deepest .gitattributes
/// above it, which wins over those further up; the splice's own, deeper still,
/// win over it. Adding it is the user's decision, and so is anything else,
/// where it wouldn't make them match.
fn refuse_monorepo_attributes(path: &str, commit: &str, tree: &str) -> Res<()> {
    let names = git(&["ls-tree", "-r", "-z", "--name-only", commit]).bytes();
    let attributes = names.and_then(|names| {
        let upstream = checkout_attributes(commit, "", &names)?;
        let monorepo = checkout_attributes(tree, &format!("{path}/"), &names)?;
        Some((names, upstream, monorepo))
    });
    let Some((names, upstream, monorepo)) = attributes else {
        return die(format!("{path}: git check-attr failed for its files"));
    };
    if upstream == monorepo {
        return Ok(());
    }
    let mut dir = path;
    let mut file = None;
    while !dir.is_empty() {
        dir = dir.rsplit_once('/').map_or("", |(above, _)| above);
        let candidate = if dir.is_empty() {
            ".gitattributes".to_string()
        } else {
            format!("{dir}/.gitattributes")
        };
        // Git doesn't read a .gitattributes that's a symbolic link.
        let listing = git(&["ls-tree", tree, "--", &candidate])
            .out()
            .unwrap_or_default();
        if listing.starts_with("100") {
            file = Some(candidate);
            break;
        }
    }
    let mut line = None;
    if let Some(file) = &file {
        let relative = if dir.is_empty() {
            path
        } else {
            path.strip_prefix(&format!("{dir}/")).unwrap_or(path)
        };
        let unset: Vec<String> = CHECKOUT_ATTRIBUTES
            .iter()
            .map(|a| format!(" !{a}"))
            .collect();
        let candidate = format!("{}{}", attributes_pattern(relative), unset.concat());
        let mut content = git(&["cat-file", "blob", &format!("{tree}:{file}")])
            .bytes()
            .unwrap_or_default();
        if !content.is_empty() && content.last() != Some(&b'\n') {
            content.push(b'\n');
        }
        content.extend_from_slice(candidate.as_bytes());
        content.push(b'\n');
        let fixes = git(&["hash-object", "-w", "--stdin"])
            .input(content)
            .out()
            .and_then(|blob| tree_with_blob(tree, file, &blob))
            .and_then(|fixed| checkout_attributes(&fixed, &format!("{path}/"), &names))
            .is_some_and(|fixed| fixed == upstream);
        if fixes {
            line = Some(candidate);
        }
    }
    if let (Some(line), Some(file)) = (line, file) {
        return die(format!(
            "{path}: attributes in {file} or above it would change how Git checks out or stores some of its files, unlike in upstream -- add '{line}' to {file}, commit it, and run clone again"
        ));
    }
    die(format!(
        "{path}: Git would check out or store some of its files otherwise than in upstream, and unsetting attributes above it can't change that"
    ))
}

fn clone_url(repo: &mut Repo, merge: bool) -> Res<i32> {
    let url = repo.args.paths[0].clone();
    if url.is_empty() {
        eprint_text(USAGE);
        return Ok(1);
    }
    let path = match repo.args.paths.get(1).filter(|path| !path.is_empty()) {
        Some(path) => path.clone(),
        None => default_clone_path(&url),
    };
    let path = normalize_path(&path);
    if path.is_empty() || path == "." || path.starts_with('/') {
        return die(format!("'{path}' isn't a folder inside the repository"));
    }
    require_usable_splice_path(&path, "choose another folder name")?;

    repo.open()?;
    let branch = current_branch()?;
    if repo.is_splice_path(&path) {
        return die(format!("{path} is a splice already"));
    }
    require_no_splice_in_progress()?;
    if path_mode("HEAD", &path) == "160000" {
        return die(format!(
            "{path} is a submodule -- 'git splice clone --from-submodule {}' turns it into a splice",
            shell_quote(&path)
        ));
    }
    if git(&["cat-file", "-e", &format!("HEAD:{path}")]).q().ok()
        && folder_tree("HEAD", &path).is_none()
    {
        return die(format!("{path} is a file, not a folder"));
    }

    let found = repo.fetch_new_upstream(&path, &url)?;
    let mut upstream_branch = branch.clone();
    if !found.monorepo_default.is_empty() && branch == found.monorepo_default {
        upstream_branch = if found.default_branch.is_empty() {
            found.container_default.clone()
        } else {
            found.default_branch.clone()
        };
    }
    if !ref_exists(&repo.splice_ref(&path, &upstream_branch)) {
        // On the monorepo's default branch inside a splice, it's the splice
        // above's default branch. The monorepo's branch name says nothing about
        // this upstream then, so it isn't tried instead.
        if found.upstream_default.is_empty() {
            return die(format!(
                "{path}: upstream has no '{upstream_branch}' branch and names no default branch"
            ));
        }
        log_step(format!(
            "{path}: upstream has no '{upstream_branch}' branch -- using '{}'; your first push creates '{upstream_branch}'",
            found.upstream_default
        ));
        upstream_branch = found.upstream_default.clone();
    }

    let target = commit_of(&repo.splice_ref(&path, &upstream_branch)).unwrap_or_default();
    if upstream_has_state_file(&target) {
        return die(format!(
            "{path}: upstream has a {STATE_FILE} at its root, which would replace {path}/{STATE_FILE} -- splice a folder of it instead"
        ));
    }
    if let Some(inner) = upstream_submodule(&target) {
        return die(format!(
            "{path}: upstream has a submodule, {inner}, which nobody could check out in the monorepo -- turn it into a splice in the upstream first"
        ));
    }
    if let Some(local) = folder_tree("HEAD", &path) {
        if Some(&local) != tree_of(&target).as_ref() && !merge {
            return die(format!(
                "{path} exists and differs from '{upstream_branch}' upstream -- '--merge' keeps both, and every file that differs becomes a conflict to resolve"
            ));
        }
    }

    let id = new_splice_id(&path, &url, &target);
    let url_key = format!("upstream.{DEFAULT_UPSTREAM}.url");
    let branch_key = format!("upstream.{DEFAULT_UPSTREAM}.default-branch");
    let blob = state_blob(
        &path,
        &[
            ("id", &id),
            ("commit", &target),
            (&url_key, &url),
            (&branch_key, &found.default_branch),
        ],
    )
    .map_err(|_| Fail::Hard)?;
    let folder = format!("{target}^{{tree}}");
    let tree = reroot_tree(&path, Some(&folder), Some(&blob), "HEAD").map_err(|_| Fail::Hard)?;
    refuse_monorepo_attributes(&path, &target, &tree)?;
    let message = repo.commit_message(format!(
        "splice: clone {path} from {upstream_branch} at {}",
        short(&target)
    ));
    // The merge base is an empty folder: the two sides share nothing.
    if splice_in(&path, None, None, &folder, &blob, &message).is_err() {
        return die(format!("{path}: clone failed"));
    }
    log_ok(format!(
        "{path}: cloned {} from {upstream_branch}",
        short(&target)
    ));
    Ok(0)
}

/// Turns the submodule at <path> into a splice; with <recursive>, its own
/// submodules too, each in a commit of its own after the one above. A submodule
/// inside a splice -- a folder above with a .splice -- is listed in that
/// folder's .gitmodules, as in its upstream.
fn clone_from_submodule(repo: &mut Repo, path: &str, recursive: bool) -> Res<i32> {
    let path = normalize_path(path);
    if path.is_empty() || path == "." || path.starts_with('/') {
        return die(format!("'{path}' isn't a folder inside the repository"));
    }
    require_usable_splice_path(&path, "rename the submodule's folder")?;

    repo.open()?;
    current_branch()?;
    if repo.is_splice_path(&path) {
        return die(format!("{path} is a splice already"));
    }
    require_no_splice_in_progress()?;
    if path_mode("HEAD", &path) != "160000" {
        return die(format!("{path}: no submodule committed here"));
    }
    let above = splice_above_in("HEAD", &path);
    let mut gitmodules = ".gitmodules".to_string();
    let mut base = String::new();
    if let Some(above) = &above {
        gitmodules = format!("{above}/.gitmodules");
        repo.require_default_upstream_of(above)?;
        base = repo.url_in_use(above);
    }
    let commit = git(&["rev-parse", &format!("HEAD:{path}")])
        .out()
        .unwrap_or_default();
    let relative = match &above {
        Some(above) => path.strip_prefix(&format!("{above}/")).unwrap_or(&path),
        None => &path,
    };
    let Some(name) = submodule_name(&gitmodules, relative) else {
        return die(format!(
            "{path}: {gitmodules} in HEAD has no submodule with this path"
        ));
    };
    let in_head = format!("HEAD:{gitmodules}");
    let setting = |key: &str| {
        git(&[
            "config",
            "--blob",
            &in_head,
            &format!("submodule.{name}.{key}"),
        ])
        .q()
        .out()
    };
    let Some(url) = setting("url") else {
        return die(format!(
            "{path}: {gitmodules} in HEAD has no url for submodule '{name}'"
        ));
    };
    let url = resolve_submodule_url(&url, &base)?;
    if setting("update").as_deref() == Some("none") {
        return die(format!(
            "{path}: update = none keeps the submodule out of every checkout, and a splice's files are always there -- remove the submodule, or unset submodule.{name}.update in {gitmodules} and commit to splice it anyway"
        ));
    }

    refuse_lossy_submodule_conversion(&path, &commit, &gitmodules)?;
    let dot_git = format!("{path}/.git");
    let mut gitdir = None;
    if Path::new(&dot_git).exists() {
        gitdir = git(&["-C", &path, "rev-parse", "--absolute-git-dir"]).out();
    }
    // The conversion above moved the repositories of nested checkouts to
    // .git/modules/; one cloned into the folder since would be lost.
    if above.is_some() && Path::new(&dot_git).is_dir() {
        return die(format!(
            "{dot_git} is a repository of its own, not one in .git/modules/ -- move it away first"
        ));
    }

    repo.register_new_upstream(&path, &url)?;
    // A commit no branch has, e.g. one only a tag has, is still there for
    // everyone if upstream serves it by id, as fetch then fetches it.
    let on_branch = git(&[
        "for-each-ref",
        "--count=1",
        "--contains",
        &commit,
        "--format=%(refname)",
        &repo.refs_prefix(&path),
    ])
    .q()
    .out()
    .unwrap_or_default();
    if on_branch.is_empty() && !fetch_by_id(&url, &commit) {
        return die(format!(
            "{path}: upstream doesn't serve the submodule's commit {} -- push it to a branch or a tag there first",
            short(&commit)
        ));
    }
    let (default_branch, pin, pinned_as) =
        repo.submodule_defaults(&path, &gitmodules, &name, &commit)?;
    if upstream_has_state_file(&commit) {
        return die(format!(
            "{path}: upstream has a {STATE_FILE} at its root, which would replace {path}/{STATE_FILE} -- splice a folder of it instead"
        ));
    }
    if let Some(inner) = upstream_submodule(&commit) {
        if !recursive {
            return die(format!(
                "{path}: the submodule has a submodule of its own, {inner} -- turn it into a splice in its upstream first, or add --recursive to convert it here too"
            ));
        }
    }
    let folder = format!("{commit}^{{tree}}");
    let tree = reroot_tree(&path, Some(&folder), None, "HEAD").map_err(|_| Fail::Hard)?;
    refuse_monorepo_attributes(&path, &commit, &tree)?;

    // Keys are submodule.<name>.<setting>, and <name> may contain dots.
    let keys = git(&[
        "config",
        "--blob",
        &in_head,
        "--name-only",
        "--get-regexp",
        r"^submodule\.",
    ])
    .out()
    .unwrap_or_default();
    for key in keys.lines() {
        let Some(setting) = key.strip_prefix(&format!("submodule.{name}.")) else {
            continue;
        };
        if !setting.contains('.') && !["path", "url", "branch"].contains(&setting) {
            log_warn(format!(
                "{path}: dropping {key} from .gitmodules -- a splice has no such setting"
            ));
        }
    }

    let id = new_splice_id(&path, &url, &commit);
    let url_key = format!("upstream.{DEFAULT_UPSTREAM}.url");
    let branch_key = format!("upstream.{DEFAULT_UPSTREAM}.default-branch");
    let pin_key = format!("upstream.{DEFAULT_UPSTREAM}.default-pin");
    let blob = state_blob(
        &path,
        &[
            ("id", &id),
            ("commit", &commit),
            (&url_key, &url),
            (&branch_key, &default_branch),
            (&pin_key, &pin),
        ],
    )
    .map_err(|_| Fail::Hard)?;
    let edited = Temp::new();
    let current = git(&["cat-file", "blob", &in_head])
        .bytes()
        .unwrap_or_default();
    if std::fs::write(&edited.path, current).is_err() {
        return Err(Fail::Hard);
    }
    let section = format!("submodule.{name}");
    must(
        git(&[
            "config",
            "--file",
            &edited.str(),
            "--remove-section",
            &section,
        ])
        .run(),
    )?;

    if gitdir.is_some() && above.is_none() {
        // An embedded repository moves to .git/modules/ first, and so do those
        // of its own submodules: removing a checkout's .git then loses nothing.
        must(git(&["submodule", "--quiet", "absorbgitdirs", "--", &path]).run())?;
        gitdir = git(&["-C", &path, "rev-parse", "--absolute-git-dir"]).out();
    }
    if gitdir.is_some() && std::fs::remove_file(&dot_git).is_err() {
        return die(format!("{dot_git}: can't remove it"));
    }
    // The monorepo's config names only its own submodules.
    if above.is_none() {
        git(&["config", "--remove-section", &section]).q().ok();
    }
    let spec = format!(":(top,literal){path}");
    must(git(&["rm", "-q", "--cached", "--", &spec]).run())?;
    must(git(&["read-tree", &format!("--prefix={path}/"), &commit]).run())?;
    // Writes only the files that are missing, as in a submodule that was never
    // checked out. A file the checks above missed, e.g. one hidden by
    // assume-unchanged, keeps its edit and shows as changed afterwards.
    let deleted = git(&["ls-files", "-z", "--deleted", "--", &spec])
        .bytes()
        .unwrap_or_default();
    must(
        git(&["checkout-index", "-z", "--stdin"])
            .input(deleted)
            .run(),
    )?;
    git(&["update-index", "-q", "--refresh"]).q().ok();
    // A commit without files left no folder to write .splice into.
    let _ = std::fs::create_dir_all(&path);
    let state_file = format!("{path}/{STATE_FILE}");
    let content = git(&["cat-file", "blob", &blob])
        .bytes()
        .unwrap_or_default();
    if std::fs::write(&state_file, content).is_err() {
        return die(format!("{state_file}: can't write it"));
    }
    must(git(&["add", "-f", "--", &state_file]).run())?;
    let left = git(&["config", "--file", &edited.str(), "--list"])
        .out()
        .unwrap_or_default();
    if left.is_empty() {
        must(git(&["rm", "-q", "--", &gitmodules]).run())?;
    } else {
        if std::fs::copy(&edited.path, &gitmodules).is_err() {
            return die(format!("{gitmodules}: can't write it"));
        }
        must(git(&["add", "--", &gitmodules]).run())?;
    }
    let message = repo.commit_message(format!(
        "splice: clone {path} from submodule at {}",
        short(&commit)
    ));
    if git(&["commit", "--quiet", "-m", &message]).run() != 0 {
        return die(format!(
            "{path}: 'git commit' failed -- the conversion stays staged"
        ));
    }
    log_ok(format!(
        "{path}: cloned {} from the submodule",
        short(&commit)
    ));
    if !pin.is_empty() {
        let tag = tag_naming(&url, &commit)
            .map(|tag| format!(", the tag '{tag}'"))
            .unwrap_or_default();
        log_step(format!(
            "{path}: pinned at {}{tag}, as {pinned_as} -- pull brings in nothing and push refuses on {} until it follows a branch: git config --file {} --unset {pin_key}",
            short(&commit),
            repo.monorepo_default_branch(),
            shell_quote(&state_file)
        ));
    }
    if let Some(gitdir) = &gitdir {
        log_step(format!(
            "{path}: the submodule's repository stays in {gitdir} -- remove it once you don't need it"
        ));
    }
    if let Some(above) = &above {
        log_step(format!(
            "{above}: upstream still has {} as a submodule -- 'git splice push {}' turns it into a splice there too",
            path.strip_prefix(&format!("{above}/")).unwrap_or(&path),
            shell_quote(above)
        ));
    }
    if !recursive {
        return Ok(0);
    }
    // Paths come from the commit, before any conversion below changes HEAD.
    let entries = git(&["ls-tree", "-r", "-z", "HEAD", "--", &spec])
        .bytes()
        .unwrap_or_default();
    let exe = std::env::current_exe().map_err(|_| Fail::Hard)?;
    for entry in nul_fields(&entries) {
        let Some((fields, sub)) = entry.split_once('\t') else {
            continue;
        };
        if !fields.starts_with("160000 ") {
            continue;
        }
        // A process each: every conversion discovers the splices anew, and a
        // refusal ends only that one.
        let converted = Command::new(&exe)
            .args(["clone", "--from-submodule", "--recursive", "--", sub])
            .status()
            .is_ok_and(|status| status.success());
        if converted {
            continue;
        }
        // Converted, but one below it wasn't: that one said so.
        if path_mode("HEAD", sub) != "160000" {
            return Ok(1);
        }
        return die(format!(
            "{sub}: not converted -- {path} and what was converted before stay; fix the above, then run 'git splice clone --from-submodule --recursive {}'",
            shell_quote(sub)
        ));
    }
    Ok(0)
}

pub fn run(argv: &[String]) -> Res<i32> {
    let args = parse_args(USAGE, "--merge --from-submodule --recursive -m", argv)?;
    let recursive = args.has_flag("--recursive");
    let merge = args.has_flag("--merge");
    if args.has_flag("--from-submodule") {
        args.require(USAGE, "clone", 1, 1)?;
        if merge {
            return die("--from-submodule takes no --merge: the folder gets the submodule's files");
        }
        if recursive && !args.message.is_empty() {
            return die("-m names one commit, and --recursive makes one per submodule");
        }
        let path = args.paths[0].clone();
        return clone_from_submodule(&mut Repo::new(args), &path, recursive);
    }
    if recursive {
        return die(
            "--recursive needs --from-submodule: it converts the submodule's own submodules too",
        );
    }
    args.require(USAGE, "clone", 1, 2)?;
    clone_url(&mut Repo::new(args), merge)
}
