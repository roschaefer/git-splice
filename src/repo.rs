//! Discovery of the splices, their upstreams, keys and targets.

use crate::args::Args;
use crate::util::*;
use std::cell::OnceCell;
use std::collections::{HashMap, HashSet};

/// Name of the state file inside every splice folder.
pub const STATE_FILE: &str = ".splice";
/// Name of the one upstream clone and init write into a new .splice.
pub const DEFAULT_UPSTREAM: &str = "origin";
const KEY_LOCK_TRIES: u32 = 50;

/// What a splice syncs with on the current branch.
#[derive(Clone, Copy, PartialEq, Debug, Default)]
pub enum TargetKind {
    #[default]
    Branch,
    Tag,
    Commit,
}

#[derive(Clone, Default, Debug)]
pub struct Target {
    pub kind: TargetKind,
    /// The branch's or tag's name, or the commit id.
    pub name: String,
    /// Its fetched ref, or the commit id.
    pub reference: String,
}

impl Target {
    /// How a status line or a commit message names it.
    pub fn label(&self) -> String {
        match self.kind {
            TargetKind::Branch => self.name.clone(),
            TargetKind::Tag => format!("tags/{}", self.name),
            TargetKind::Commit => short(&self.name).to_string(),
        }
    }

    /// How a sentence names it.
    pub fn description(&self) -> String {
        match self.kind {
            TargetKind::Tag => format!("the tag '{}'", self.name),
            TargetKind::Commit => format!("the commit {}", short(&self.name)),
            TargetKind::Branch => format!("the '{}' branch", self.name),
        }
    }

    pub fn kind_name(&self) -> &'static str {
        match self.kind {
            TargetKind::Branch => "branch",
            TargetKind::Tag => "tag",
            TargetKind::Commit => "commit",
        }
    }
}

/// A splice's sync state.
#[derive(Clone, Copy, PartialEq, Debug, Default)]
pub enum State {
    #[default]
    NeverFetched,
    MissingBranch,
    MissingPin,
    MissingSynced,
    UpToDate,
    Push,
    Pull,
    Diverged,
    UnrelatedHistory,
}

/// Results of classify_splice, for the splice classified last.
#[derive(Clone, Default, Debug)]
pub struct Classified {
    pub state: State,
    pub upstream_branch: String,
    pub upstream_label: String,
    pub target: Target,
    pub target_ref: String,
    pub synced: String,
    pub rebuilt: String,
}

/// Results of compare_with_default_branch.
#[derive(Clone, Default, Debug)]
pub struct Compared {
    pub rebuilt: String,
    pub default_branch: String,
    pub default_ref: String,
    pub new_commits: String,
    pub behind_commits: String,
    pub no_changes: bool,
}

#[derive(Default)]
pub struct Repo {
    pub args: Args,
    pub all_paths: Vec<String>,
    pub upstream_lists: HashMap<String, Vec<String>>,
    pub upstream_urls: HashMap<(String, String), String>,
    pub default_upstreams: HashMap<String, String>,
    pub upstream_names: HashMap<String, String>,
    pub urls: HashMap<String, String>,
    pub keys: HashMap<String, String>,
    pub selected: Vec<String>,
    pub monorepo_branch: String,
    tracked: HashMap<String, String>,
    tracked_for: Option<String>,
    key_of_url: HashMap<String, String>,
    url_of_key: HashMap<String, String>,
    keys_loaded: bool,
    monorepo_default: OnceCell<String>,
    empty_tree: OnceCell<String>,
    pub uncommitted: HashMap<String, Uncommitted>,
    pub content_tree_cache: HashMap<String, String>,
    pub rebuild_given: HashMap<String, String>,
    pub rebuild_without_synced: bool,
    pub joins_rewritten: bool,
    pub merge_bump: bool,
    pub merge_rebase: bool,
    pub merge_no_fork_point: bool,
    pub c: Classified,
    pub d: Compared,
}

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Uncommitted {
    Changes,
    NoChanges,
    Failed,
}

/// Whether a command needs paths or --all, or looks at every splice otherwise.
#[derive(Clone, Copy, PartialEq)]
pub enum Kind {
    Explicit,
    Overview,
}

/// Holds the lock on the upstream keys while it lives.
pub struct KeyLock {
    path: String,
}

impl Drop for KeyLock {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir(&self.path);
    }
}

/// Upstream commit <commit> has a state file at its root: bringing it in
/// would replace the splice's own.
pub fn upstream_has_state_file(commit: &str) -> bool {
    git(&["cat-file", "-e", &format!("{commit}:{STATE_FILE}")])
        .q()
        .ok()
}

/// The folder's tree in commit <rev>, if there's a folder there.
pub fn folder_tree(rev: &str, path: &str) -> Option<String> {
    let object = git(&["rev-parse", "--verify", "--quiet", &format!("{rev}:{path}")])
        .q()
        .out()?;
    (git(&["cat-file", "-t", &object]).out().as_deref() == Some("tree")).then_some(object)
}

/// Value <key> of splice <path>'s state file as committed in <rev>, or nothing.
pub fn splice_config(path: &str, key: &str, rev: &str) -> String {
    git(&[
        "config",
        "--blob",
        &format!("{rev}:{path}/{STATE_FILE}"),
        "--get",
        &format!("splice.{key}"),
    ])
    .q()
    .out()
    .unwrap_or_default()
}

/// Value <key> of upstream <name> in splice <path>'s committed state file.
pub fn upstream_config(path: &str, name: &str, key: &str) -> String {
    if name.is_empty() {
        return String::new();
    }
    git(&[
        "config",
        "--blob",
        &format!("HEAD:{path}/{STATE_FILE}"),
        "--get",
        &format!("upstream.{name}.{key}"),
    ])
    .q()
    .out()
    .unwrap_or_default()
}

/// The nearest splice above splice <path> in commit <rev>: the closest folder
/// above it with a state file.
pub fn splice_above_in(rev: &str, path: &str) -> Option<String> {
    let mut dir = path;
    while let Some((above, _)) = dir.rsplit_once('/') {
        dir = above;
        if git(&["cat-file", "-e", &format!("{rev}:{dir}/{STATE_FILE}")])
            .q()
            .ok()
        {
            return Some(dir.to_string());
        }
    }
    None
}

pub fn commit_here(commit: &str) -> bool {
    git(&["cat-file", "-e", &format!("{commit}^{{commit}}")])
        .q()
        .ok()
}

pub fn is_ancestor(ancestor: &str, descendant: &str) -> bool {
    git(&["merge-base", "--is-ancestor", ancestor, descendant]).ok()
}

pub fn commit_of(rev: &str) -> Option<String> {
    git(&[
        "rev-parse",
        "--verify",
        "--quiet",
        &format!("{rev}^{{commit}}"),
    ])
    .out()
}

pub fn tree_of(rev: &str) -> Option<String> {
    git(&["rev-parse", &format!("{rev}^{{tree}}")]).out()
}

pub fn ref_exists(reference: &str) -> bool {
    git(&["show-ref", "--verify", "--quiet", reference]).ok()
}

/// Succeeds if <path> would be valid in a ref name. Splice paths were part of
/// their refs' names before refs were keyed by URL, and are still limited to
/// these until every command is tested with the others.
pub fn usable_splice_path(path: &str) -> bool {
    git(&["check-ref-format", &format!("refs/splices/{path}/branch")]).ok()
}

pub fn require_usable_splice_path(path: &str, fix: &str) -> Res<()> {
    if usable_splice_path(path) {
        return Ok(());
    }
    die(format!(
        "'{path}' isn't supported as a splice path yet -- {fix} (e.g. no spaces)"
    ))
}

fn valid_upstream_name(name: &str) -> bool {
    let mut chars = name.chars();
    chars.next().is_some_and(|c| c.is_ascii_alphanumeric())
        && chars.all(|c| c.is_ascii_alphanumeric() || "._-".contains(c))
}

pub fn valid_upstream_key(key: &str) -> bool {
    let edge = |c: char| c.is_ascii_lowercase() || c.is_ascii_digit();
    !key.is_empty()
        && key.len() <= 64
        && key.chars().next().is_some_and(edge)
        && key.chars().last().is_some_and(edge)
        && key.chars().all(|c| edge(c) || "._-".contains(c))
        && git(&[
            "check-ref-format",
            &format!("refs/splices/{key}/heads/main"),
        ])
        .ok()
}

/// <name> as a valid key, or nothing if nothing usable is left: lower case,
/// with anything a key can't hold replaced by "-", and its end kept if it's
/// too long.
fn upstream_key_candidate(name: &str) -> String {
    let mut name: String = name
        .bytes()
        .map(|b| {
            let c = (b as char).to_ascii_lowercase();
            if c.is_ascii_lowercase() || c.is_ascii_digit() || "._-".contains(c) {
                c
            } else {
                '-'
            }
        })
        .collect();
    while name.contains("--") {
        name = name.replace("--", "-");
    }
    while name.contains("..") {
        name = name.replace("..", ".");
    }
    if name.len() > 60 {
        name = name[name.len() - 60..].to_string();
    }
    let name = name.trim_matches(|c| "._-".contains(c)).to_string();
    let name = match name.strip_suffix(".lock") {
        Some(stem) => format!("{stem}-lock"),
        None => name,
    };
    if valid_upstream_key(&name) {
        name
    } else {
        String::new()
    }
}

/// The keys upstream <url> could get, most readable first: its last path
/// component without .git, then with more of the path in front, up to the
/// host. Falls back to "upstream" if no part of the URL is usable.
fn upstream_key_candidates(url: &str) -> Vec<String> {
    let rest = url.split_once("://").map_or(url, |(_, rest)| rest);
    let rest = rest.trim_end_matches('/');
    let rest = rest.strip_suffix(".git").unwrap_or(rest);
    let mut candidates: Vec<String> = Vec::new();
    let mut name = String::new();
    for part in rest.split(['/', ':']).rev() {
        let part = part.rsplit('@').next().unwrap_or(part);
        if part.is_empty() {
            continue;
        }
        name = if name.is_empty() {
            part.to_string()
        } else {
            format!("{part}-{name}")
        };
        let candidate = upstream_key_candidate(&name);
        if !candidate.is_empty() && !candidates.contains(&candidate) {
            candidates.push(candidate);
        }
    }
    if candidates.is_empty() {
        candidates.push("upstream".to_string());
    }
    candidates
}

pub fn is_commit_id(name: &str) -> bool {
    (name.len() == 40 || name.len() == 64)
        && name
            .chars()
            .all(|c| c.is_ascii_digit() || ('a'..='f').contains(&c))
}

/// Prints splice paths one per line, in tree order: top-down, each after every
/// splice above it, or bottom-up, each before them. Trees, and subtrees under
/// the same splice, keep the order given, each at the place of its first path.
pub fn splices_in_order(bottom_up: bool, paths: &[String]) -> Vec<String> {
    let given: HashSet<&str> = paths.iter().map(String::as_str).collect();
    let mut parent_of: HashMap<String, String> = HashMap::new();
    let mut children: HashMap<String, Vec<String>> = HashMap::new();
    let mut roots: Vec<String> = Vec::new();
    for path in paths {
        let mut node = path.clone();
        while !parent_of.contains_key(&node) {
            let mut parent = String::new();
            let mut dir = node.as_str();
            while let Some((above, _)) = dir.rsplit_once('/') {
                dir = above;
                if given.contains(dir) {
                    parent = dir.to_string();
                    break;
                }
            }
            parent_of.insert(node.clone(), parent.clone());
            if parent.is_empty() {
                roots.push(node);
                break;
            }
            children.entry(parent.clone()).or_default().push(node);
            node = parent;
        }
    }
    fn walk(
        nodes: &[String],
        children: &HashMap<String, Vec<String>>,
        bottom_up: bool,
        out: &mut Vec<String>,
    ) {
        for node in nodes {
            if !bottom_up {
                out.push(node.clone());
            }
            if let Some(below) = children.get(node) {
                walk(below, children, bottom_up, out);
            }
            if bottom_up {
                out.push(node.clone());
            }
        }
    }
    let mut out = Vec::new();
    walk(&roots, &children, bottom_up, &mut out);
    out
}

pub fn first_above(below: &str, paths: &[String]) -> Option<String> {
    paths
        .iter()
        .find(|path| below.starts_with(&format!("{path}/")))
        .cloned()
}

pub fn first_below(above: &str, paths: &[String]) -> Option<String> {
    paths
        .iter()
        .find(|path| path.starts_with(&format!("{above}/")))
        .cloned()
}

/// A cherry-pick, merge or rebase waits to be concluded.
pub fn splice_in_progress() -> bool {
    git(&["rev-parse", "--quiet", "--verify", "CHERRY_PICK_HEAD"])
        .q()
        .ok()
        || git(&["rev-parse", "--quiet", "--verify", "MERGE_HEAD"])
            .q()
            .ok()
        || rebase_in_progress()
}

pub fn rebase_in_progress() -> bool {
    ["rebase-merge", "rebase-apply"].iter().any(|dir| {
        git(&["rev-parse", "--git-path", dir])
            .out()
            .is_some_and(|path| std::path::Path::new(&path).is_dir())
    })
}

pub fn require_no_splice_in_progress() -> Res<()> {
    if splice_in_progress() {
        return die("a cherry-pick, merge or rebase is in progress -- conclude it first");
    }
    Ok(())
}

/// The current local branch; ends the command on detached HEAD, since every
/// splice syncs with the upstream branch named like the current one.
pub fn current_branch() -> Res<String> {
    match git(&["symbolic-ref", "--quiet", "--short", "HEAD"]).out() {
        Some(branch) => Ok(branch),
        None => die("not on a branch (detached HEAD) -- git splice requires a named branch"),
    }
}

impl Repo {
    pub fn new(args: Args) -> Repo {
        Repo {
            args,
            ..Repo::default()
        }
    }

    /// Where every command starts: at the repository root, with HEAD a commit,
    /// and the splices discovered.
    pub fn open(&mut self) -> Res<()> {
        let Some(toplevel) = git(&["rev-parse", "--show-toplevel"]).q().out() else {
            return die("not inside a git repository");
        };
        if std::env::set_current_dir(&toplevel).is_err() {
            return die(format!("failed to cd to repo root: {toplevel}"));
        }
        if !git(&["rev-parse", "--quiet", "--verify", "HEAD^{commit}"]).ok() {
            let branch = current_branch()?;
            return die(format!(
                "branch '{branch}' has no commits yet -- create one and re-run: git commit --allow-empty -m 'initial commit'"
            ));
        }
        self.discover_splices()
    }

    pub fn empty_tree(&self) -> String {
        self.empty_tree
            .get_or_init(|| {
                git(&["hash-object", "-t", "tree", "/dev/null"])
                    .out()
                    .unwrap_or_default()
            })
            .clone()
    }

    /// Every state file in commit <commit>, at any depth.
    pub fn state_files(&self, commit: &str) -> Vec<String> {
        let spec = format!(":(top,glob)**/{STATE_FILE}");
        let output = git(&[
            "diff-tree",
            "-r",
            "--name-only",
            "-z",
            &self.empty_tree(),
            commit,
            "--",
            &spec,
        ])
        .q()
        .bytes()
        .unwrap_or_default();
        nul_fields(&output)
    }

    /// A folder with a committed .splice is a splice, also below another
    /// splice. Committed, not staged: every command reads a splice's state
    /// from HEAD.
    pub fn discover_splices(&mut self) -> Res<()> {
        self.all_paths.clear();
        for file in self.state_files("HEAD") {
            if file == STATE_FILE {
                return die(format!(
                    "a {STATE_FILE} at the repository root isn't supported -- a splice must be a folder"
                ));
            }
            let path = file
                .strip_suffix(&format!("/{STATE_FILE}"))
                .unwrap_or(&file)
                .to_string();
            require_usable_splice_path(&path, "rename the folder")?;
            self.all_paths.push(path);
        }
        for path in self.all_paths.clone() {
            self.load_splice_upstream(&path)?;
        }
        Ok(())
    }

    pub fn is_splice_path(&self, path: &str) -> bool {
        self.all_paths.iter().any(|p| p == path)
    }

    pub fn require_splice(&self, path: &str) -> Res<()> {
        if self.is_splice_path(path) {
            return Ok(());
        }
        die(format!("not a splice: {path}"))
    }

    /// Resolves which splices a command acts on, into `selected`.
    pub fn select_paths(&mut self, kind: Kind, command: &str) -> Res<()> {
        self.selected.clear();
        if self.args.all && !self.args.paths.is_empty() {
            return die("give either paths or --all, not both");
        }
        if self.args.paths.is_empty() {
            if kind == Kind::Explicit && !self.args.all {
                let splices = if self.all_paths.is_empty() {
                    "none".to_string()
                } else {
                    self.all_paths.join(" ")
                };
                return die(format!(
                    "which splice? -- name one or more paths, or pass --all (splices: {splices})"
                ));
            }
            self.selected = self.all_paths.clone();
            if self.selected.is_empty() {
                return die(format!("no splices found -- nothing to {command}"));
            }
            return Ok(());
        }
        for path in self.args.paths.clone() {
            let path = normalize_path(&path);
            self.require_splice(&path)?;
            if !self.selected.contains(&path) {
                self.selected.push(path);
            }
        }
        Ok(())
    }

    /// Selects the splices, makes each use the upstream --upstream names, or
    /// its default one, and sets the monorepo's branch. Ends the command
    /// before any splice is touched unless each has something to sync with.
    pub fn select_splices(&mut self, kind: Kind, command: &str) -> Res<()> {
        self.select_paths(kind, command)?;
        let upstream = self.args.upstream.clone();
        let selected = self.selected.clone();
        self.use_upstreams(&upstream, &selected)?;
        self.monorepo_branch = current_branch()?;
        let branch = self.monorepo_branch.clone();
        self.load_tracked_branches(&branch);
        for path in &selected {
            self.resolve_upstream_target(path, &branch)?;
        }
        Ok(())
    }

    /// Reads the upstreams of splice <path> from its committed state file, and
    /// uses its default one, or ends the command explaining what's wrong with
    /// the file.
    pub fn load_splice_upstream(&mut self, path: &str) -> Res<()> {
        let blob = format!("HEAD:{path}/{STATE_FILE}");
        let Some((status, output)) = git(&["config", "--blob", &blob, "--list", "-z"])
            .q()
            .bytes_and_status()
        else {
            return die(format!("{path}/{STATE_FILE} can't be read"));
        };
        if !status.success() {
            let error = git(&["config", "--blob", &blob, "--list"]).err_text();
            let error = error.lines().next().unwrap_or("");
            let error = error.strip_prefix("error: ").unwrap_or(error);
            return die(format!(
                "{path}/{STATE_FILE} can't be read ({error}) -- fix it and commit it"
            ));
        }
        let mut urls: Vec<String> = Vec::new();
        let mut names: Vec<String> = Vec::new();
        let mut seen: Vec<String> = Vec::new();
        let mut defaults: Vec<String> = Vec::new();
        let mut id = String::new();
        let mut default = String::new();
        for record in nul_fields(&output) {
            // <key>, a newline, and the value -- or only <key>, for a key
            // without "= <value>", which git config --get reads as empty.
            let (key, value) = record.split_once('\n').unwrap_or((&record, ""));
            if let Some(name) = key
                .strip_prefix("upstream.")
                .and_then(|rest| rest.strip_suffix(".url"))
            {
                if !valid_upstream_name(name) {
                    return die(format!(
                        "{path}/{STATE_FILE}: '{name}' isn't supported as an upstream's name -- use letters, digits, '.', '_' and '-'"
                    ));
                }
                if seen.iter().any(|s| s == name) {
                    return die(format!(
                        "{path}/{STATE_FILE} names upstream '{name}' twice -- keep one"
                    ));
                }
                seen.push(name.to_string());
                // An empty URL names no upstream.
                if !value.is_empty() {
                    urls.push(value.to_string());
                    names.push(name.to_string());
                }
            } else if key == "splice.id" {
                id = value.to_string();
            } else if key == "splice.default-upstream" {
                default = value.to_string();
            } else if key == "splice.default-branch" {
                return die(format!(
                    "{path}/{STATE_FILE} has default-branch in [splice], from an earlier version -- it belongs to an upstream now: upstream.<name>.default-branch"
                ));
            } else if key.starts_with("upstream.")
                && (key.ends_with(".default-branch") || key.ends_with(".default-pin"))
            {
                defaults.push(key[..key.rfind('.').unwrap_or(key.len())].to_string());
            }
        }
        let q_file = shell_quote(&format!("{path}/{STATE_FILE}"));
        defaults.sort();
        if let Some(name) = defaults.windows(2).find(|pair| pair[0] == pair[1]) {
            let name = &name[0];
            return die(format!(
                "{path}/{STATE_FILE} has both default-branch and default-pin for {name} -- follow the branch or pin, not both: git config --file {q_file} --unset {name}.default-pin"
            ));
        }
        if urls.is_empty() {
            return die(format!(
                "{path}/{STATE_FILE} names no upstream -- add one: git config --file {q_file} upstream.{DEFAULT_UPSTREAM}.url <url>"
            ));
        }
        if !default.is_empty() && !names.contains(&default) {
            return die(format!(
                "{path}/{STATE_FILE}: default-upstream '{default}' isn't one of its upstreams ({}) -- fix it: git config --file {q_file} splice.default-upstream <name>",
                join_names(&names)
            ));
        }
        if id.is_empty() {
            return die(format!("{path}/{STATE_FILE} has no id"));
        }
        if names.len() <= 1 {
            default = names[0].clone();
        }
        for (name, url) in names.iter().zip(&urls) {
            self.upstream_urls
                .insert((path.to_string(), name.clone()), url.clone());
        }
        self.upstream_lists.insert(path.to_string(), names);
        self.default_upstreams
            .insert(path.to_string(), default.clone());
        if default.is_empty() {
            self.upstream_names.insert(path.to_string(), String::new());
            self.urls.insert(path.to_string(), String::new());
            self.keys.insert(path.to_string(), String::new());
            Ok(())
        } else {
            self.use_upstream(path, &default)
        }
    }

    /// Makes commands use upstream <name> of splice <path>.
    pub fn use_upstream(&mut self, path: &str, name: &str) -> Res<()> {
        let url = self.url_of(path, name);
        self.upstream_names
            .insert(path.to_string(), name.to_string());
        self.urls.insert(path.to_string(), url.clone());
        let key = self.upstream_key(&url)?;
        self.keys.insert(path.to_string(), key);
        Ok(())
    }

    pub fn url_of(&self, path: &str, name: &str) -> String {
        self.upstream_urls
            .get(&(path.to_string(), name.to_string()))
            .cloned()
            .unwrap_or_default()
    }

    pub fn name_of(&self, path: &str) -> String {
        self.upstream_names.get(path).cloned().unwrap_or_default()
    }

    pub fn key_of(&self, path: &str) -> String {
        self.keys.get(path).cloned().unwrap_or_default()
    }

    pub fn url_in_use(&self, path: &str) -> String {
        self.urls.get(path).cloned().unwrap_or_default()
    }

    fn has_several_upstreams(&self, path: &str) -> bool {
        self.upstream_lists.get(path).is_some_and(|l| l.len() > 1)
    }

    pub fn several_upstreams(&self, path: &str) -> bool {
        self.has_several_upstreams(path)
    }

    /// Upstream branch <branch> of splice <path> as messages name it: <branch>,
    /// or <name>/<branch> of the upstream in use if the splice has several.
    pub fn upstream_branch_label(&self, path: &str, branch: &str) -> String {
        if self.has_several_upstreams(path) {
            format!("{}/{branch}", self.name_of(path))
        } else {
            branch.to_string()
        }
    }

    /// --branch names splice <path>'s upstream branch: the command selected
    /// it, not only a splice above it.
    pub fn branch_arg_applies(&self, path: &str) -> bool {
        !self.args.branch.is_empty() && self.selected.iter().any(|p| p == path)
    }

    /// Reads the upstream branches tracked on monorepo branch <branch>, by
    /// upstream key; the last entry for a key wins.
    pub fn load_tracked_branches(&mut self, branch: &str) {
        self.tracked.clear();
        self.tracked_for = Some(branch.to_string());
        let entries = git(&[
            "config",
            "--local",
            "--get-all",
            &format!("branch.{branch}.splice"),
        ])
        .q()
        .out()
        .unwrap_or_default();
        for entry in entries.lines() {
            if let Some((key, name)) = entry.split_once(':') {
                if !key.is_empty() && !name.is_empty() {
                    self.tracked.insert(key.to_string(), name.to_string());
                }
            }
        }
    }

    /// The upstream branch tracked for splice <path>'s upstream in use, while
    /// the monorepo is on <branch>; nothing if none is.
    pub fn tracked_branch(&mut self, path: &str, branch: &str) -> String {
        let key = self.key_of(path);
        if key.is_empty() {
            return String::new();
        }
        if self.tracked_for.as_deref() != Some(branch) {
            self.load_tracked_branches(branch);
        }
        self.tracked.get(&key).cloned().unwrap_or_default()
    }

    /// The upstream branch named for splice <path> beyond the rule of the same
    /// name: --branch's, else the tracked one.
    pub fn named_branch(&mut self, path: &str, branch: &str) -> Option<String> {
        if self.branch_arg_applies(path) {
            return Some(self.args.branch.clone());
        }
        let name = self.tracked_branch(path, branch);
        (!name.is_empty()).then_some(name)
    }

    /// Splice <path>'s upstream key, or a failure explaining that a fetch
    /// records one, for what <action> needs it.
    fn key_to_track(&self, path: &str, action: &str) -> Res<String> {
        let key = self.key_of(path);
        if key.is_empty() {
            return fail(format!(
                "{path}: its upstream has no key yet, which {action} needs -- 'git splice fetch {}' records one",
                shell_quote(path)
            ));
        }
        Ok(key)
    }

    /// Tracks upstream branch <name> for splice <path>'s upstream, by its key,
    /// while the monorepo is on <branch>.
    pub fn track_branch(&mut self, path: &str, branch: &str, name: &str) -> Res<()> {
        let key = self.key_to_track(path, &format!("tracking '{name}'"))?;
        let setting = format!("branch.{branch}.splice");
        let pattern = format!("^{}:", key.replace('.', "\\."));
        git(&["config", "--local", "--unset-all", &setting, &pattern])
            .q()
            .ok();
        if !git(&[
            "config",
            "--local",
            "--add",
            &setting,
            &format!("{key}:{name}"),
        ])
        .ok()
        {
            return fail(format!("{path}: couldn't track '{name}' in {setting}"));
        }
        self.tracked_for = None;
        log_ok(format!(
            "{path}: '{branch}' tracks '{}' from now on",
            self.upstream_branch_label(path, name)
        ));
        Ok(())
    }

    /// Stops tracking a branch for splice <path>'s upstream while the monorepo
    /// is on <branch>.
    pub fn untrack_branch(&mut self, path: &str, branch: &str) -> Res<()> {
        let name = self.tracked_branch(path, branch);
        if name.is_empty() {
            log_ok(format!(
                "{path}: '{branch}' tracks no branch of its upstream"
            ));
            return Ok(());
        }
        let key = self.key_to_track(path, "--no-track")?;
        let setting = format!("branch.{branch}.splice");
        let pattern = format!("^{}:", key.replace('.', "\\."));
        if !git(&["config", "--local", "--unset-all", &setting, &pattern]).ok() {
            return fail(format!("{path}: couldn't remove '{name}' from {setting}"));
        }
        self.tracked_for = None;
        log_ok(format!(
            "{path}: '{branch}' no longer tracks '{}'",
            self.upstream_branch_label(path, &name)
        ));
        Ok(())
    }

    /// "--upstream <name> " if splice <path> uses another upstream than its
    /// default, for the commands that messages suggest.
    pub fn upstream_option(&self, path: &str) -> String {
        let name = self.name_of(path);
        if self
            .default_upstreams
            .get(path)
            .cloned()
            .unwrap_or_default()
            == name
        {
            String::new()
        } else {
            format!("--upstream {name} ")
        }
    }

    /// The options that select splice <path>'s upstream and branch in this
    /// command, for the commands that messages suggest.
    pub fn selection_options(&self, path: &str) -> String {
        let mut options = self.upstream_option(path);
        if self.branch_arg_applies(path) {
            options.push_str(&format!("--branch {} ", shell_quote(&self.args.branch)));
        }
        options
    }

    fn require_default_upstream(&self, path: &str) -> Res<()> {
        if !self
            .default_upstreams
            .get(path)
            .cloned()
            .unwrap_or_default()
            .is_empty()
        {
            return Ok(());
        }
        let names = self.upstream_lists.get(path).cloned().unwrap_or_default();
        die(format!(
            "{path} names upstreams {}, but no default -- pass --upstream <name>, or commit one: git config --file {} splice.default-upstream <name>",
            join_names(&names),
            shell_quote(&format!("{path}/{STATE_FILE}"))
        ))
    }

    pub fn require_default_upstream_of(&self, path: &str) -> Res<()> {
        self.require_default_upstream(path)
    }

    /// Makes each of splices <paths> use its upstream <name>, or its default
    /// one if <name> is empty. Ends the command before any splice is touched
    /// if one of them lacks it: falling back to another upstream would pull
    /// from, or push to, a repository nobody named.
    pub fn use_upstreams(&mut self, name: &str, paths: &[String]) -> Res<()> {
        let mut missing: Vec<String> = Vec::new();
        let mut having: Vec<String> = Vec::new();
        for path in paths {
            self.require_upstream_list(path)?;
            if name.is_empty() {
                self.require_default_upstream(path)?;
            } else if self.upstream_lists[path].iter().any(|n| n == name) {
                having.push(path.clone());
            } else {
                missing.push(path.clone());
            }
        }
        if !missing.is_empty() {
            if paths.len() == 1 {
                let names = &self.upstream_lists[&paths[0]];
                if names.len() == 1 {
                    return die(format!(
                        "{} has no upstream '{name}' -- its upstream is '{}'",
                        paths[0], names[0]
                    ));
                }
                return die(format!(
                    "{} has no upstream '{name}' -- its upstreams are {}",
                    paths[0],
                    join_names(names)
                ));
            }
            if having.is_empty() {
                return die(format!(
                    "none of these splices has an upstream '{name}': {}",
                    missing.join(" ")
                ));
            }
            return die(format!(
                "no upstream '{name}' in {} -- name only the splices that have one: {}",
                missing.join(" "),
                having.join(" ")
            ));
        }
        for path in paths {
            let chosen = if name.is_empty() {
                self.default_upstreams[path].clone()
            } else {
                name.to_string()
            };
            self.use_upstream(path, &chosen)?;
        }
        Ok(())
    }

    fn load_upstream_keys(&mut self) -> Res<()> {
        if self.keys_loaded {
            return Ok(());
        }
        let output = git(&[
            "config",
            "--local",
            "-z",
            "--get-regexp",
            r"^splice\..*\.url$",
        ])
        .q()
        .bytes()
        .unwrap_or_default();
        for record in nul_fields(&output) {
            let (key, url) = record.split_once('\n').unwrap_or((&record, ""));
            let key = key.strip_prefix("splice.").unwrap_or(key);
            let key = key.strip_suffix(".url").unwrap_or(key);
            if !valid_upstream_key(key) {
                return die(format!(
                    "splice.{key}.url in the repository's config: '{key}' isn't a valid key -- rename it: git config --local --rename-section {} splice.<new-key>",
                    shell_quote(&format!("splice.{key}"))
                ));
            }
            if url.is_empty() {
                return die(format!(
                    "splice.{key}.url in the repository's config is empty -- remove it: git config --local --remove-section splice.{key}"
                ));
            }
            if self.url_of_key.contains_key(key) {
                return die(format!(
                    "splice.{key}.url is set more than once in the repository's config -- keep one: git config --local --edit"
                ));
            }
            if let Some(other) = self.key_of_url.get(url) {
                return die(format!(
                    "keys '{other}' and '{key}' both name {url} in the repository's config -- remove one: git config --local --remove-section splice.{key}"
                ));
            }
            self.url_of_key.insert(key.to_string(), url.to_string());
            self.key_of_url.insert(url.to_string(), key.to_string());
        }
        self.keys_loaded = true;
        Ok(())
    }

    fn reload_upstream_keys(&mut self) -> Res<()> {
        self.keys_loaded = false;
        self.key_of_url.clear();
        self.url_of_key.clear();
        self.load_upstream_keys()
    }

    /// The key the fetched refs of upstream <url> live under, or nothing if it
    /// has never been fetched. The URL is taken exactly as written.
    pub fn upstream_key(&mut self, url: &str) -> Res<String> {
        self.load_upstream_keys()?;
        if let Some(key) = self.key_of_url.get(url) {
            return Ok(key.clone());
        }
        // Not cached: another command may have recorded it since.
        self.reload_upstream_keys()?;
        Ok(self.key_of_url.get(url).cloned().unwrap_or_default())
    }

    pub fn url_for_key(&self, key: &str) -> Option<String> {
        self.url_of_key.get(key).cloned()
    }

    fn upstream_key_taken(&mut self, key: &str) -> Res<bool> {
        self.load_upstream_keys()?;
        if self.url_of_key.contains_key(key) {
            return Ok(true);
        }
        Ok(
            !git(&["for-each-ref", "--count=1", &format!("refs/splices/{key}")])
                .out()
                .unwrap_or_default()
                .is_empty(),
        )
    }

    /// Takes the lock on the upstream keys: a folder in the repository's common
    /// Git directory, which mkdir creates or fails on in one step.
    pub fn lock_upstream_keys(&self) -> Res<KeyLock> {
        let dir = git(&["rev-parse", "--path-format=absolute", "--git-common-dir"])
            .out()
            .unwrap_or_default();
        let lock = format!("{dir}/splice-keys.lock");
        for _ in 0..KEY_LOCK_TRIES {
            if std::fs::create_dir(&lock).is_ok() {
                return Ok(KeyLock { path: lock });
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
        die(format!(
            "another git splice is recording an upstream key -- if none is running, remove {lock}"
        ))
    }

    /// Upstream <url>'s key, recording one in the repository's config first if
    /// it has none: the first candidate that's free, or the last with "-2",
    /// "-3" and so on. Under the lock, so two commands recording keys at the
    /// same time can't pick the same one.
    pub fn create_upstream_key(&mut self, url: &str) -> Res<String> {
        let key = self.upstream_key(url)?;
        if !key.is_empty() {
            return Ok(key);
        }
        let _lock = self.lock_upstream_keys()?;
        self.reload_upstream_keys()?;
        if let Some(key) = self.key_of_url.get(url) {
            return Ok(key.clone());
        }
        let candidates = upstream_key_candidates(url);
        let mut key = String::new();
        for candidate in &candidates {
            if !self.upstream_key_taken(candidate)? {
                key = candidate.clone();
                break;
            }
        }
        if key.is_empty() {
            let last = &candidates[candidates.len() - 1];
            let mut n = 2;
            while self.upstream_key_taken(&format!("{last}-{n}"))? {
                n += 1;
            }
            key = format!("{last}-{n}");
        }
        if !git(&["config", "--local", &format!("splice.{key}.url"), url]).ok() {
            return die(format!(
                "couldn't record the key of {url} in the repository's config"
            ));
        }
        self.url_of_key.insert(key.clone(), url.to_string());
        self.key_of_url.insert(url.to_string(), key.clone());
        Ok(key)
    }

    /// Rereads the keys under a lock taken for a rename.
    pub fn reread_upstream_keys(&mut self) -> Res<()> {
        self.reload_upstream_keys()
    }

    pub fn key_taken(&mut self, key: &str) -> Res<bool> {
        self.upstream_key_taken(key)
    }

    /// Gives splice <path>'s upstream a key, if it has none yet, and every
    /// splice with the same URL along with it.
    pub fn ensure_splice_key(&mut self, path: &str) -> Res<()> {
        self.require_splice_upstream(path)?;
        if !self.key_of(path).is_empty() {
            return Ok(());
        }
        let url = self.url_in_use(path);
        let key = self.create_upstream_key(&url)?;
        let same: Vec<String> = self
            .urls
            .iter()
            .filter(|(_, u)| **u == url)
            .map(|(p, _)| p.clone())
            .collect();
        for path in same {
            self.keys.insert(path, key.clone());
        }
        Ok(())
    }

    /// The ref prefix splice <path>'s fetched upstream branches share. An
    /// upstream without a key has no refs: its prefix isn't a valid ref name,
    /// so it matches none.
    pub fn refs_prefix(&self, path: &str) -> String {
        let key = self.key_of(path);
        format!(
            "refs/splices/{}/heads/",
            if key.is_empty() { "." } else { &key }
        )
    }

    pub fn splice_ref(&self, path: &str, branch: &str) -> String {
        format!("{}{branch}", self.refs_prefix(path))
    }

    /// Loads splice <path>'s upstreams, unless discovery or clone has.
    pub fn require_upstream_list(&mut self, path: &str) -> Res<()> {
        if !self.upstream_lists.contains_key(path) {
            self.load_splice_upstream(path)?;
        }
        Ok(())
    }

    /// Loads splice <path>'s upstreams if needed, ends the command unless one
    /// is in use, and looks up its key again if it had none yet.
    pub fn require_splice_upstream(&mut self, path: &str) -> Res<()> {
        self.require_upstream_list(path)?;
        if self.name_of(path).is_empty() {
            self.require_default_upstream(path)?;
        }
        if self.key_of(path).is_empty() {
            let url = self.url_in_use(path);
            let key = self.upstream_key(&url)?;
            self.keys.insert(path.to_string(), key);
        }
        Ok(())
    }

    /// Any upstream branch of the splice has been fetched.
    pub fn splice_fetched(&self, path: &str) -> bool {
        !self.key_of(path).is_empty()
            && !git(&["for-each-ref", "--count=1", &self.refs_prefix(path)])
                .out()
                .unwrap_or_default()
                .is_empty()
    }

    /// The monorepo's default branch: the target of origin/HEAD, else
    /// init.defaultBranch, else nothing.
    pub fn monorepo_default_branch(&self) -> String {
        self.monorepo_default
            .get_or_init(|| {
                let name = git(&[
                    "symbolic-ref",
                    "--quiet",
                    "--short",
                    "refs/remotes/origin/HEAD",
                ])
                .q()
                .out()
                .unwrap_or_default();
                if !name.is_empty() {
                    return name.strip_prefix("origin/").unwrap_or(&name).to_string();
                }
                git(&["config", "--get", "init.defaultBranch"])
                    .q()
                    .out()
                    .unwrap_or_default()
            })
            .clone()
    }

    /// The default branch of upstream <upstream> of the splice, or of the one
    /// it uses: that upstream's recorded default-branch, else the one of what
    /// it lives in. A .splice records it only where it differs from that, so
    /// the file means the same in every repository it reaches.
    pub fn splice_default_branch(&mut self, path: &str, upstream: Option<&str>) -> Res<String> {
        let upstream = upstream.map_or_else(|| self.name_of(path), str::to_string);
        let name = upstream_config(path, &upstream, "default-branch");
        if !name.is_empty() {
            return Ok(name);
        }
        self.container_default_branch(path)
    }

    fn followed_default_branch(
        &mut self,
        path: &str,
        above: &str,
        upstream: Option<&str>,
    ) -> Res<String> {
        let target = self.resolve_default_target(above, upstream)?;
        if target.kind != TargetKind::Branch {
            return die(format!(
                "{path} follows the default branch of {above}, which pins {} -- record one for {path}: git config --file {} upstream.<name>.default-branch <branch>",
                target.description(),
                shell_quote(&format!("{path}/{STATE_FILE}"))
            ));
        }
        Ok(target.name)
    }

    /// The default branch of what folder <path> lives in: the default branch of
    /// the upstream the splice above it uses, or the monorepo's. Ends the
    /// command if that splice names several upstreams with different default
    /// branches, but none is chosen.
    pub fn container_default_branch(&mut self, path: &str) -> Res<String> {
        let Some(above) = splice_above_in("HEAD", path) else {
            return Ok(self.monorepo_default_branch());
        };
        self.require_upstream_list(&above)?;
        if !self.name_of(&above).is_empty() {
            return self.followed_default_branch(path, &above, None);
        }
        let names = self.upstream_lists[&above].clone();
        let mut branches = Vec::new();
        let mut seen: Vec<String> = Vec::new();
        let mut branch = String::new();
        for name in &names {
            branch = self.followed_default_branch(path, &above, Some(name))?;
            branches.push(format!("{name}: {branch}"));
            if !seen.contains(&branch) {
                seen.push(branch.clone());
            }
        }
        if seen.len() > 1 {
            return die(format!(
                "{path} follows the default branch of {above}, whose upstreams have different default branches ({}), but no default -- commit one: git config --file {} splice.default-upstream <name>",
                branches.join(", "),
                shell_quote(&format!("{above}/{STATE_FILE}"))
            ));
        }
        Ok(branch)
    }

    /// The upstream branch the splice syncs with, from its upstream <upstream>
    /// or the one it uses, while the monorepo is on <branch>.
    pub fn upstream_branch_for(
        &mut self,
        path: &str,
        branch: &str,
        upstream: Option<&str>,
    ) -> Res<String> {
        if upstream.is_none() || upstream == Some(self.name_of(path).as_str()) {
            if let Some(name) = self.named_branch(path, branch) {
                return Ok(name);
            }
        }
        if self.branch_arg_applies(path) {
            Ok(self.args.branch.clone())
        } else if branch == self.monorepo_default_branch() {
            self.splice_default_branch(path, upstream)
        } else {
            Ok(branch.to_string())
        }
    }

    fn resolve_branch(&self, path: &str, name: &str) -> Target {
        Target {
            kind: TargetKind::Branch,
            name: name.to_string(),
            reference: self.splice_ref(path, name),
        }
    }

    fn resolve_pin(&self, path: &str, name: &str, pin: &str) -> Res<Target> {
        if is_commit_id(pin) {
            return Ok(Target {
                kind: TargetKind::Commit,
                name: pin.to_string(),
                reference: pin.to_string(),
            });
        }
        let key = self.key_of(path);
        let prefix = format!("refs/splices/{}/", if key.is_empty() { "." } else { &key });
        let reference = format!("{prefix}tags/{pin}");
        if !ref_exists(&reference) && ref_exists(&format!("{prefix}heads/{pin}")) {
            let q_file = shell_quote(&format!("{path}/{STATE_FILE}"));
            return die(format!(
                "{path}: default-pin names '{pin}', a branch upstream, not a tag -- to follow it: git config --file {q_file} upstream.{name}.default-branch {} && git config --file {q_file} --unset upstream.{name}.default-pin",
                shell_quote(pin)
            ));
        }
        Ok(Target {
            kind: TargetKind::Tag,
            name: pin.to_string(),
            reference,
        })
    }

    /// What the monorepo's default branch syncs the splice with, from its
    /// upstream <upstream> or the one it uses: the tag or commit that
    /// upstream's default-pin names, else its default branch.
    pub fn resolve_default_target(&mut self, path: &str, upstream: Option<&str>) -> Res<Target> {
        let name = upstream.map_or_else(|| self.name_of(path), str::to_string);
        let pin = upstream_config(path, &name, "default-pin");
        if !pin.is_empty() {
            return self.resolve_pin(path, &name, &pin);
        }
        let branch = self.splice_default_branch(path, Some(&name))?;
        Ok(self.resolve_branch(path, &branch))
    }

    /// What the splice syncs with while the monorepo is on <branch>.
    pub fn resolve_upstream_target(&mut self, path: &str, branch: &str) -> Res<Target> {
        if self.named_branch(path, branch).is_none() && branch == self.monorepo_default_branch() {
            self.resolve_default_target(path, None)
        } else {
            let name = self.upstream_branch_for(path, branch, None)?;
            Ok(self.resolve_branch(path, &name))
        }
    }

    /// Whether the splice's folder has uncommitted changes.
    pub fn has_uncommitted_changes(&mut self, path: &str) -> Uncommitted {
        if !self.uncommitted.contains_key(path) {
            self.load_uncommitted_changes(&[path.to_string()]);
        }
        self.uncommitted[path]
    }

    /// Asks git status once for all of the splices. A change in a splice below
    /// another counts for both. No renames: one from a splice to outside it
    /// still lists the file it removed from the splice.
    pub fn load_uncommitted_changes(&mut self, paths: &[String]) {
        let specs: Vec<String> = paths.iter().map(|p| format!(":(top,literal){p}")).collect();
        let mut args = vec![
            "status",
            "--porcelain",
            "-z",
            "--no-renames",
            "--untracked-files=normal",
            "--",
        ];
        args.extend(specs.iter().map(String::as_str));
        let Some(output) = git(&args).q().bytes() else {
            for path in paths {
                self.uncommitted.insert(path.clone(), Uncommitted::Failed);
            }
            return;
        };
        for path in paths {
            self.uncommitted
                .insert(path.clone(), Uncommitted::NoChanges);
        }
        for entry in nul_fields(&output) {
            // "XY <file>", where an untracked folder ends with "/".
            let file = entry.get(3..).unwrap_or("");
            for path in paths {
                if file == path
                    || file.starts_with(&format!("{path}/"))
                    || (file.ends_with('/') && format!("{path}/").starts_with(file))
                {
                    self.uncommitted.insert(path.clone(), Uncommitted::Changes);
                }
            }
        }
    }

    /// The message -m gave, else <default>: the message of the commit a command
    /// writes.
    pub fn commit_message(&self, default: String) -> String {
        if self.args.message.is_empty() {
            default
        } else {
            self.args.message.clone()
        }
    }
}
