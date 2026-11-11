//! What a drawing is checked against: the monorepo's commits and refs, read
//! once and kept, and what git-splice says about each splice, from its own
//! code.

use git_splice::context::ExecutionContext;
use git_splice::rebuild::{has_parent, splice_lineage, splice_lineage_to_mount};
use git_splice::repo::{current_branch, Repo};
use git_splice::util::{git, quietly, Res};
use std::cell::{OnceCell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

/// What a copy shares with the commit it copies, read the way the rebuild's
/// copy_commit reads it: author, committer and the whole message.
const COPY_KEY_FORMAT: &str = "%an%n%ae%n%aD%n%cn%n%ce%n%cD%n%B";

/// A commit's hash and subject.
pub struct Subject {
    pub hash: String,
    pub subject: String,
}

/// The folders splice <path> had on HEAD's first-parent history, as the
/// rebuild follows it back through moves (`git mv`): the mount (nothing if
/// there's none), then each path and the range (rev-list syntax) of commits it
/// applies to, newest first. The last range starts at the mount: before, the
/// folder was no splice, or another one.
pub struct Lineage {
    pub mount: String,
    pub segments: Vec<(String, String)>,
}

/// What H, B, T, R, U(H) and U(B) of a splice name, and what else the checks
/// read about it.
#[derive(Default)]
pub struct Truth {
    pub b: String,
    /// U(H): the commit HEAD's .splice records.
    pub u: String,
    /// U(B): the commit B's .splice records.
    pub s: String,
    pub t: String,
    pub r: String,
    /// merge-base(R,T).
    pub base: String,
    pub key: String,
    /// Every commit the splice's .splice recorded on HEAD's first-parent
    /// history.
    pub synced: Vec<String>,
}

#[derive(Default)]
pub struct History {
    /// Each commit's parents, for every commit read so far.
    parents: RefCell<HashMap<String, Vec<String>>>,
    all_read: OnceCell<()>,
    ancestors: RefCell<HashMap<String, Rc<HashSet<String>>>>,
    /// Each ref and the commit it points at, sorted by name.
    refs: OnceCell<Vec<(String, String)>>,
    revisions: RefCell<HashMap<String, Option<String>>>,
    copy_keys: RefCell<HashMap<String, String>>,
    logs: RefCell<HashMap<Vec<String>, Rc<Vec<Subject>>>>,
    keyed_logs: RefCell<HashMap<Vec<String>, Rc<Vec<String>>>>,
    config: RefCell<HashMap<(String, String), String>>,
    lineages: RefCell<HashMap<String, Rc<Lineage>>>,
    upstream_keys: RefCell<HashMap<(String, String), String>>,
    upstream_names: RefCell<HashMap<String, Rc<Vec<String>>>>,
    state_files: RefCell<HashMap<String, Rc<Vec<String>>>>,
}

fn is_hash(rev: &str) -> bool {
    (rev.len() == 40 || rev.len() == 64) && rev.bytes().all(|b| b.is_ascii_hexdigit())
}

/// Runs a git-splice step on a repository of its own, the way `git splice`
/// runs one command, without its messages: what fails is nothing.
fn splice_step<T>(step: impl FnOnce(&mut Repo) -> Res<T>) -> Option<T> {
    quietly(|| {
        let mut context = ExecutionContext::new();
        let mut repo = Repo::new(&mut context, Default::default());
        repo.open().ok()?;
        step(&mut repo).ok()
    })
}

impl History {
    fn add_parents(&self, output: &str) {
        let mut parents = self.parents.borrow_mut();
        for line in output.lines() {
            let mut hashes = line.split(' ').map(str::to_string);
            if let Some(commit) = hashes.next() {
                parents.insert(commit, hashes.collect());
            }
        }
    }

    /// Reads the parents of commit <commit> and of everything before it.
    fn read_commit(&self, commit: &str) {
        self.all_read.get_or_init(|| {
            let output = git(&["rev-list", "--parents", "--all"])
                .q()
                .out()
                .unwrap_or_default();
            self.add_parents(&output);
        });
        if !commit.is_empty() && !self.parents.borrow().contains_key(commit) {
            // Not on a ref, e.g. R: rebuilt, but kept nowhere.
            let output = git(&["rev-list", "--parents", commit, "--not", "--all"])
                .q()
                .out()
                .unwrap_or_default();
            self.add_parents(&output);
        }
    }

    /// The commit revision <rev> names, if it names one.
    pub fn commit(&self, rev: &str) -> Option<String> {
        if rev.is_empty() {
            return None;
        }
        if is_hash(rev) && self.parents.borrow().contains_key(rev) {
            return Some(rev.to_string());
        }
        self.rev_parse(&format!("{rev}^{{commit}}"))
    }

    /// `git rev-parse --verify --quiet <rev>`.
    pub fn rev_parse(&self, rev: &str) -> Option<String> {
        if let Some(known) = self.revisions.borrow().get(rev) {
            return known.clone();
        }
        let found = git(&["rev-parse", "--verify", "--quiet", rev])
            .q()
            .out()
            .filter(|hash| !hash.is_empty());
        self.revisions
            .borrow_mut()
            .insert(rev.to_string(), found.clone());
        found
    }

    /// Commit <commit>'s parents, in order.
    pub fn parents_of(&self, commit: &str) -> Vec<String> {
        self.read_commit(commit);
        self.parents
            .borrow()
            .get(commit)
            .cloned()
            .unwrap_or_default()
    }

    fn ancestors_of(&self, commit: &str) -> Rc<HashSet<String>> {
        if let Some(known) = self.ancestors.borrow().get(commit) {
            return known.clone();
        }
        self.read_commit(commit);
        let mut seen = HashSet::new();
        if self.parents.borrow().contains_key(commit) {
            let mut todo = vec![commit.to_string()];
            while let Some(next) = todo.pop() {
                if seen.contains(&next) {
                    continue;
                }
                if !self.parents.borrow().contains_key(&next) {
                    self.read_commit(&next);
                }
                if let Some(parents) = self.parents.borrow().get(&next) {
                    todo.extend(parents.iter().filter(|p| !seen.contains(*p)).cloned());
                }
                seen.insert(next);
            }
        }
        let seen = Rc::new(seen);
        self.ancestors
            .borrow_mut()
            .insert(commit.to_string(), seen.clone());
        seen
    }

    /// `git merge-base --is-ancestor <ancestor> <descendant>`.
    pub fn is_ancestor(&self, ancestor: &str, descendant: &str) -> bool {
        let (Some(ancestor), Some(descendant)) = (self.commit(ancestor), self.commit(descendant))
        else {
            return false;
        };
        self.ancestors_of(&descendant).contains(&ancestor)
    }

    /// `git merge-base <a> <b>`.
    pub fn merge_base(&self, a: &str, b: &str) -> Option<String> {
        git(&["merge-base", a, b])
            .q()
            .out()
            .filter(|hash| !hash.is_empty())
    }

    fn refs(&self) -> &[(String, String)] {
        self.refs.get_or_init(|| {
            let output = git(&[
                "for-each-ref",
                "--format=%(refname)%09%(objecttype)%09%(objectname)%09%(*objectname)",
            ])
            .q()
            .out()
            .unwrap_or_default();
            output
                .lines()
                .filter_map(|line| {
                    let mut fields = line.split('\t');
                    let name = fields.next()?;
                    let kind = fields.next()?;
                    let object = fields.next()?;
                    let peeled = fields.next().unwrap_or("");
                    let commit = match kind {
                        "commit" => object,
                        "tag" if !peeled.is_empty() => peeled,
                        _ => return None,
                    };
                    Some((name.to_string(), commit.to_string()))
                })
                .collect()
        })
    }

    /// The first ref, by name, below <prefix>, e.g. `refs/heads/`, that has
    /// commit <commit>: `git for-each-ref --count=1 --contains`.
    pub fn first_ref_containing(&self, commit: &str, prefixes: &[&str]) -> Option<String> {
        if commit.is_empty() {
            return None;
        }
        self.refs()
            .iter()
            .filter(|(name, _)| prefixes.iter().any(|prefix| name.starts_with(prefix)))
            .find(|(_, tip)| self.is_ancestor(commit, tip))
            .map(|(name, _)| name.clone())
    }

    pub fn any_ref_contains(&self, commit: &str, prefixes: &[&str]) -> bool {
        self.first_ref_containing(commit, prefixes).is_some()
    }

    /// Hash and subject of each commit `git log <args>` lists, in its order.
    pub fn log(&self, args: &[String]) -> Rc<Vec<Subject>> {
        if let Some(known) = self.logs.borrow().get(args) {
            return known.clone();
        }
        let mut argv = vec!["log", "--format=%H%x09%s"];
        argv.extend(args.iter().map(String::as_str));
        let output = git(&argv).q().out().unwrap_or_default();
        let subjects = Rc::new(
            output
                .lines()
                .filter_map(|line| {
                    let (hash, subject) = line.split_once('\t')?;
                    Some(Subject {
                        hash: hash.to_string(),
                        subject: subject.to_string(),
                    })
                })
                .collect::<Vec<_>>(),
        );
        self.logs
            .borrow_mut()
            .insert(args.to_vec(), subjects.clone());
        subjects
    }

    /// The commits `git log <args>` lists, in its order, with their copy keys
    /// read along.
    pub fn log_with_copy_keys(&self, args: &[String]) -> Rc<Vec<String>> {
        if let Some(known) = self.keyed_logs.borrow().get(args) {
            return known.clone();
        }
        let format = format!("--pretty=format:%H%n{COPY_KEY_FORMAT}");
        let mut argv = vec![
            "-c",
            "i18n.commitEncoding=UTF-8",
            "-c",
            "i18n.logOutputEncoding=UTF-8",
            "log",
            "-z",
            "--no-show-signature",
            &format,
        ];
        argv.extend(args.iter().map(String::as_str));
        let output = git(&argv).q().bytes().unwrap_or_default();
        let mut hashes = Vec::new();
        let mut keys = self.copy_keys.borrow_mut();
        for record in output.split(|&byte| byte == 0).filter(|r| !r.is_empty()) {
            let record = String::from_utf8_lossy(record);
            let (hash, key) = record.split_once('\n').unwrap_or((&record, ""));
            keys.insert(hash.to_string(), key.to_string());
            hashes.push(hash.to_string());
        }
        let hashes = Rc::new(hashes);
        self.keyed_logs
            .borrow_mut()
            .insert(args.to_vec(), hashes.clone());
        hashes
    }

    /// What a copy of commit <commit> shares with it.
    pub fn copy_key(&self, commit: &str) -> String {
        if !self.copy_keys.borrow().contains_key(commit) {
            self.log_with_copy_keys(&["--no-walk".to_string(), commit.to_string()]);
        }
        self.copy_keys
            .borrow()
            .get(commit)
            .cloned()
            .unwrap_or_default()
    }

    /// The whole message of commit <commit>.
    pub fn message(&self, commit: &str) -> String {
        git(&["log", "-1", "--format=%B", commit])
            .q()
            .out()
            .unwrap_or_default()
    }

    /// `git config --blob <blob> <key>`: nothing if it's not set or there's
    /// no such blob.
    pub fn config(&self, blob: &str, key: &str) -> String {
        let at = (blob.to_string(), key.to_string());
        if let Some(known) = self.config.borrow().get(&at) {
            return known.clone();
        }
        let value = git(&["config", "--blob", blob, key])
            .q()
            .out()
            .unwrap_or_default();
        self.config.borrow_mut().insert(at, value.clone());
        value
    }

    /// The upstream branch tracked for the upstream with key <key> on monorepo
    /// branch <branch>, as git-splice reads branch.<b>.splice: the last entry
    /// for the key wins.
    pub fn tracked_name(&self, branch: &str, key: &str) -> String {
        let entries = git(&["config", "--get-all", &format!("branch.{branch}.splice")])
            .q()
            .out()
            .unwrap_or_default();
        let prefix = format!("{key}:");
        entries
            .lines()
            .rev()
            .find_map(|entry| entry.strip_prefix(&prefix))
            .unwrap_or("")
            .to_string()
    }

    /// Every state file in commit <commit>, at any depth.
    pub fn state_files(&self, commit: &str) -> Rc<Vec<String>> {
        if let Some(known) = self.state_files.borrow().get(commit) {
            return known.clone();
        }
        let mut context = ExecutionContext::new();
        let files = Rc::new(Repo::new(&mut context, Default::default()).state_files(commit));
        self.state_files
            .borrow_mut()
            .insert(commit.to_string(), files.clone());
        files
    }

    /// The splices on HEAD.
    pub fn splices(&self) -> Vec<String> {
        self.state_files("HEAD")
            .iter()
            .filter_map(|file| file.strip_suffix("/.splice"))
            .map(str::to_string)
            .collect()
    }

    /// The names of the upstreams splice <path>'s .splice names.
    pub fn upstream_names(&self, path: &str) -> Rc<Vec<String>> {
        if let Some(known) = self.upstream_names.borrow().get(path) {
            return known.clone();
        }
        let output = git(&[
            "config",
            "--blob",
            &format!("HEAD:{path}/.splice"),
            "--name-only",
            "--get-regexp",
            r"^upstream\..*\.url$",
        ])
        .q()
        .out()
        .unwrap_or_default();
        let names = Rc::new(
            output
                .lines()
                .map(|line| {
                    let name = line.strip_prefix("upstream.").unwrap_or(line);
                    name.strip_suffix(".url").unwrap_or(name).to_string()
                })
                .collect::<Vec<_>>(),
        );
        self.upstream_names
            .borrow_mut()
            .insert(path.to_string(), names.clone());
        names
    }

    /// The key of splice <path>'s upstream <name>, as `git splice key
    /// --upstream <name>` prints it: nothing if it was never fetched.
    pub fn upstream_key(&self, path: &str, name: &str) -> String {
        let at = (path.to_string(), name.to_string());
        if let Some(known) = self.upstream_keys.borrow().get(&at) {
            return known.clone();
        }
        let key = splice_step(|repo| {
            repo.require_splice(path)?;
            repo.use_upstreams(name, &[path.to_string()])?;
            Ok(repo.key_of(path))
        })
        .unwrap_or_default();
        self.upstream_keys.borrow_mut().insert(at, key.clone());
        key
    }

    pub fn lineage(&self, path: &str) -> Rc<Lineage> {
        if let Some(known) = self.lineages.borrow().get(path) {
            return known.clone();
        }
        let to_sync = splice_lineage(path, "HEAD");
        let to_mount = splice_lineage_to_mount(&to_sync.path, &to_sync.upper);
        let mut segments: Vec<(String, String)> = to_sync
            .moves
            .iter()
            .chain(&to_mount.moves)
            .map(|segment| (segment.path.clone(), segment.range.clone()))
            .collect();
        let last = if to_mount.mount.is_empty() || !has_parent(&to_mount.mount) {
            to_mount.upper.clone()
        } else {
            format!("{}^1..{}", to_mount.mount, to_mount.upper)
        };
        segments.push((to_mount.path.clone(), last));
        let lineage = Rc::new(Lineage {
            mount: to_mount.mount,
            segments,
        });
        self.lineages
            .borrow_mut()
            .insert(path.to_string(), lineage.clone());
        lineage
    }

    /// The folder splice <path> had in monorepo commit <commit>: in a commit
    /// after the mount, the one whose .splice has the splice's id there, like
    /// the rebuild tells it, also on a branch that moved the splice on its
    /// own, merged or not. Otherwise, or where no folder or several (mirrors)
    /// have the id, the one HEAD's first-parent history had, at the fork for a
    /// commit on another branch; nothing before the mount, where another
    /// splice may have the id, e.g. the mirror this one was copied from.
    pub fn path_at(&self, path: &str, commit: &str) -> String {
        let lineage = self.lineage(path);
        if !lineage.mount.is_empty() && self.is_ancestor(&lineage.mount, commit) {
            let id = self.config(&format!("HEAD:{path}/.splice"), "splice.id");
            let found: Vec<String> = self
                .state_files(commit)
                .iter()
                .filter(|file| self.config(&format!("{commit}:{file}"), "splice.id") == id)
                .map(|file| file.strip_suffix("/.splice").unwrap_or(file).to_string())
                .collect();
            if let [folder] = found.as_slice() {
                return folder.clone();
            }
        }
        let commit = if self.is_ancestor(commit, "HEAD") {
            commit.to_string()
        } else if let Some(fork) = self.merge_base("HEAD", commit) {
            fork
        } else {
            return String::new();
        };
        for (folder, range) in &lineage.segments {
            let (lower, upper) = match range.split_once("..") {
                Some((lower, upper)) => (lower, upper),
                None => ("", range.as_str()),
            };
            if self.is_ancestor(&commit, upper)
                && (lower.is_empty() || !self.is_ancestor(&commit, lower))
            {
                return folder.clone();
            }
        }
        String::new()
    }

    /// What H, B, T, R and the rest name for splice <path>.
    pub fn truth(&self, path: &str) -> Truth {
        let mut truth = Truth::default();
        // Each as its own `git splice` command would tell it: one failing
        // leaves the others.
        if let Some((b, r, key, t)) = splice_step(|repo| {
            repo.require_splice(path)?;
            let b = repo
                .splice_start(path, "HEAD")
                .ok()
                .flatten()
                .unwrap_or_default();
            let r = repo
                .rebuild_splice(path, "HEAD")
                .ok()
                .flatten()
                .unwrap_or_default();
            // `git splice key`: the default upstream's.
            let key = repo
                .use_upstreams("", &[path.to_string()])
                .map(|()| repo.key_of(path))
                .unwrap_or_default();
            // The fetched ref of what the splice syncs with on the current
            // branch.
            let t = (|| -> Res<String> {
                repo.require_splice_upstream(path)?;
                let branch = current_branch()?;
                let upstream_branch = repo.upstream_branch_for(path, &branch, None)?;
                Ok(repo.splice_ref(path, &upstream_branch))
            })()
            .unwrap_or_default();
            Ok((b, r, key, t))
        }) {
            truth.b = b;
            truth.r = r;
            truth.key = key;
            truth.t = self.rev_parse(&t).unwrap_or_default();
        }
        truth.u = self.config(&format!("HEAD:{path}/.splice"), "splice.commit");
        if !truth.b.is_empty() {
            let at = self.path_at(path, &truth.b);
            truth.s = self.config(&format!("{}:{at}/.splice", truth.b), "splice.commit");
        }
        if !truth.r.is_empty() && !truth.t.is_empty() {
            truth.base = self.merge_base(&truth.r, &truth.t).unwrap_or_default();
        }
        for (folder, range) in &self.lineage(path).segments {
            let commits = git(&[
                "log",
                "--first-parent",
                "--format=%H",
                range,
                "--",
                &format!("{folder}/.splice"),
            ])
            .q()
            .out()
            .unwrap_or_default();
            for commit in commits.lines() {
                let synced = self.config(&format!("{commit}:{folder}/.splice"), "splice.commit");
                if !synced.is_empty() {
                    truth.synced.push(synced);
                }
            }
        }
        truth
    }

    /// The pulls commit <commit> records: each state file, with the synced
    /// commit its first parent records and its own, where they differ. A
    /// state file the parent lacks, as after a clone, records none; one
    /// whose parent records no synced commit yet, as after an init, does.
    pub fn pulls_in(&self, commit: &str) -> Vec<(String, String, String)> {
        let Some(parent) = self.parents_of(commit).first().cloned() else {
            return Vec::new();
        };
        let mut pulls = Vec::new();
        for file in self.state_files(commit).iter() {
            let now = self.config(&format!("{commit}:{file}"), "splice.commit");
            let earlier = format!("{parent}:{file}");
            if now.is_empty() || self.rev_parse(&earlier).is_none() {
                continue;
            }
            let before = self.config(&earlier, "splice.commit");
            if before != now {
                pulls.push((file.clone(), before, now));
            }
        }
        pulls
    }

    /// What the next rebuilds of the splices with facts <truths> do: the
    /// monorepo commits they walk, on the first-parent history since each
    /// B, and the copy keys of the commits they copy, since each S.
    pub fn walked_and_copied<'t>(
        &self,
        truths: impl Iterator<Item = &'t Truth>,
    ) -> (HashSet<String>, HashSet<String>) {
        let (mut walked, mut copied) = (HashSet::new(), HashSet::new());
        for truth in truths {
            if truth.b.is_empty() {
                continue;
            }
            if !truth.r.is_empty() {
                let mut range = vec![truth.r.clone()];
                if !truth.s.is_empty() {
                    range.push(format!("^{}", truth.s));
                }
                for commit in self.log_with_copy_keys(&range).iter() {
                    copied.insert(self.copy_key(commit));
                }
            }
            walked.extend(self.first_parent_since(&truth.b));
            // Where the splice starts, the rebuild walks B too, and copies it,
            // e.g. right after init.
            if copied.contains(&self.copy_key(&truth.b)) {
                walked.insert(truth.b.clone());
            }
        }
        (walked, copied)
    }

    /// The pulls among commits <commits>, at any level, so a pulled commit
    /// can be followed out through the splices around it: each commit whose
    /// .splice for a splice inside it records another synced commit than its
    /// first parent's, and the upstream commits each brought in, in the new
    /// synced commit's history but not the old one's, or all of it after an
    /// init, which recorded none. A commit that adds a .splice, like a
    /// clone's, records no pull. Copies of the pulling repository's own
    /// commits, on its first-parent history, came back from a push, not in
    /// with the pull.
    pub fn pulls_among(&self, commits: &[String]) -> (HashSet<String>, HashSet<String>) {
        let (mut pulls, mut brought) = (HashSet::new(), HashSet::new());
        for commit in commits {
            let Some(parent) = self.parents_of(commit).first().cloned() else {
                continue;
            };
            for (_, before, now) in self.pulls_in(commit) {
                pulls.insert(commit.clone());
                let own: HashSet<String> = self
                    .log_with_copy_keys(&["--first-parent".to_string(), parent.clone()])
                    .iter()
                    .map(|commit| self.copy_key(commit))
                    .collect();
                let mut range = vec![now];
                if !before.is_empty() {
                    range.push(format!("^{before}"));
                }
                for subject in self.log(&range).iter() {
                    if !own.contains(&self.copy_key(&subject.hash)) {
                        brought.insert(subject.hash.clone());
                    }
                }
            }
        }
        (pulls, brought)
    }

    pub fn head(&self) -> String {
        self.rev_parse("HEAD").unwrap_or_default()
    }

    /// The first-parent history from B to HEAD, which the rebuild walks.
    pub fn first_parent_since(&self, boundary: &str) -> HashSet<String> {
        let output = git(&["rev-list", "--first-parent", &format!("{boundary}..HEAD")])
            .q()
            .out()
            .unwrap_or_default();
        output.lines().map(str::to_string).collect()
    }
}
