//! The push rebuild: turns a splice's history in the monorepo into the commits
//! its upstream gets. The rebuild is deterministic -- the same history always
//! rebuilds into the same commits -- so status can compare it with the upstream
//! branch without remembering anything about earlier pushes. See
//! docs/design/README.md.

use crate::repo::*;
use crate::util::*;

/// For every git command that reads or writes a rebuilt commit: the rebuild
/// must come out the same for everyone, and i18n.commitEncoding would re-encode
/// each message and add an encoding header.
const ENCODING: [&str; 4] = [
    "-c",
    "i18n.commitEncoding=UTF-8",
    "-c",
    "i18n.logOutputEncoding=UTF-8",
];

fn encoded_git(args: &[&str]) -> Git {
    let mut all: Vec<&str> = ENCODING.to_vec();
    all.extend_from_slice(args);
    git(&all)
}

/// Where a commit's metadata comes from for a copy of it.
struct Copied<'a> {
    author: &'a [u8],
    email: &'a [u8],
    date: &'a [u8],
    committer: &'a [u8],
    committer_email: &'a [u8],
    committer_date: &'a [u8],
    message: &'a [u8],
}

fn os(bytes: &[u8]) -> &std::ffi::OsStr {
    use std::os::unix::ffi::OsStrExt;
    std::ffi::OsStr::from_bytes(bytes)
}

/// A new commit with <tree> and <parents> that copies author, committer and
/// message, the way `git subtree split` does. Never signed: a signature would
/// make the result differ from run to run.
fn write_copy(copied: &Copied, tree: &str, parents: &[String]) -> Res<String> {
    let mut args = vec!["commit-tree", "--no-gpg-sign", tree];
    for parent in parents {
        args.push("-p");
        args.push(parent);
    }
    let commit = encoded_git(&args)
        .env("GIT_AUTHOR_NAME", os(copied.author))
        .env("GIT_AUTHOR_EMAIL", os(copied.email))
        .env("GIT_AUTHOR_DATE", os(copied.date))
        .env("GIT_COMMITTER_NAME", os(copied.committer))
        .env("GIT_COMMITTER_EMAIL", os(copied.committer_email))
        .env("GIT_COMMITTER_DATE", os(copied.committer_date))
        .input(copied.message)
        .out();
    commit.ok_or(Fail::Soft)
}

const COPY_FORMAT: &str = "%an%x00%ae%x00%aD%x00%cn%x00%ce%x00%cD%x00%B";

fn copy_commit(source: &str, tree: &str, parents: &[String]) -> Res<String> {
    // --pretty=format: has no trailing newline, unlike --format= (tformat), so
    // the message comes out byte for byte as split copies it.
    let format = format!("--pretty=format:{COPY_FORMAT}");
    let output = encoded_git(&["log", "-1", "--no-show-signature", &format, source])
        .bytes()
        .ok_or(Fail::Soft)?;
    let fields: Vec<&[u8]> = output.splitn(7, |&byte| byte == 0).collect();
    if fields.len() != 7 {
        return Err(Fail::Soft);
    }
    write_copy(
        &Copied {
            author: fields[0],
            email: fields[1],
            date: fields[2],
            committer: fields[3],
            committer_email: fields[4],
            committer_date: fields[5],
            message: fields[6],
        },
        tree,
        parents,
    )
}

/// Where a splice came from, read off a commit that moved it.
#[derive(Default)]
struct Moved {
    from: String,
    state_kept: bool,
}

/// A newer path of a splice, and the range of commits it applies to.
#[derive(Clone)]
pub struct Segment {
    pub path: String,
    pub range: String,
}

pub struct Lineage {
    pub last_sync: String,
    pub synced: String,
    pub path: String,
    pub before_path: String,
    pub upper: String,
    pub moves: Vec<Segment>,
}

pub struct MountLineage {
    pub mount: String,
    pub path: String,
    pub upper: String,
    pub moves: Vec<Segment>,
}

fn upper_of(range: &str) -> &str {
    range.split_once("..").map_or(range, |(_, upper)| upper)
}

fn lower_of(range: &str) -> &str {
    range.split_once("..").map_or(range, |(lower, _)| lower)
}

pub fn has_parent(rev: &str) -> bool {
    git(&["rev-parse", "--verify", "--quiet", &format!("{rev}^1")])
        .q()
        .ok()
}

/// The newest first-parent commit reachable from <rev> that changed the
/// splice's state file: the last sync, L. Every pull, clone and init writes
/// such a commit, and rebases and squash merges can't remove all of them.
fn splice_last_sync(path: &str, rev: &str) -> String {
    let spec = format!(":(top,literal){path}/{STATE_FILE}");
    git(&[
        "log",
        "--first-parent",
        "-1",
        "--no-show-signature",
        "--format=%H",
        rev,
        "--",
        &spec,
    ])
    .out()
    .unwrap_or_default()
}

/// A shallow clone's cut-off commit looks like the splice's last sync or mount
/// whether it is one or not, and the rebuild would fold the commits since the
/// real one into one.
fn refuse_shallow_start(name: &str, commit: &str) -> Res<()> {
    let shallow = git(&["rev-parse", "--git-path", "shallow"])
        .out()
        .unwrap_or_default();
    let cut_off =
        std::fs::read_to_string(shallow).is_ok_and(|file| file.lines().any(|line| line == commit));
    if cut_off {
        return fail(format!(
            "{name}: this shallow clone may cut off where its rebuild starts, at {} -- run 'git fetch --unshallow'",
            short(commit)
        ));
    }
    Ok(())
}

fn same_splice(path: &str, a: &str, b: &str, path_b: &str) -> bool {
    let id = splice_config(path, "id", a);
    !id.is_empty() && id == splice_config(path_b, "id", b)
}

fn tree_lines(rev_path: &str) -> Vec<String> {
    let mut lines: Vec<String> = git(&["ls-tree", "-r", rev_path])
        .out()
        .unwrap_or_default()
        .lines()
        .map(str::to_string)
        .collect();
    lines.sort();
    lines
}

/// The folder that commit <rev> moved splice <path> from, if it did. The
/// splice's id says where it came from: the folder whose state file had that
/// id in <rev>'s first parent, and no longer has it in <rev>. If several
/// folders had the id, mirrors moved together, the one with the most files
/// unchanged at <path> wins, and on a tie the one with <path>'s folder name;
/// otherwise it's no move.
fn moved_from(rev: &str, path: &str) -> Moved {
    let mut moved = Moved::default();
    let id = splice_config(path, "id", rev);
    if id.is_empty() {
        return moved;
    }
    let parent = format!("{rev}^1");
    // Most often, as at a pull, the same splice was there before: no move.
    if splice_config(path, "id", &parent) == id || !has_parent(rev) {
        return moved;
    }
    let spec = format!(":(top,glob)**/{STATE_FILE}");
    let changed = git(&[
        "diff-tree",
        "-r",
        "-z",
        "--no-renames",
        "--name-only",
        "--diff-filter=DM",
        &parent,
        rev,
        "--",
        &spec,
    ])
    .bytes()
    .unwrap_or_default();
    let mut candidates: Vec<String> = Vec::new();
    for file in nul_fields(&changed) {
        let from = file
            .strip_suffix(&format!("/{STATE_FILE}"))
            .unwrap_or(&file)
            .to_string();
        if from != path
            && splice_config(&from, "id", &parent) == id
            && splice_config(&from, "id", rev) != id
        {
            candidates.push(from);
        }
    }
    if candidates.len() == 1 {
        moved.from = candidates.remove(0);
    } else if !candidates.is_empty() {
        let here = tree_lines(&format!("{rev}:{path}"));
        let mut best: Vec<String> = Vec::new();
        let mut best_score = -1i64;
        for from in candidates {
            // Files with the same name and content: lines both listings have.
            let score = tree_lines(&format!("{parent}:{from}"))
                .iter()
                .filter(|line| here.binary_search(line).is_ok())
                .count() as i64;
            if score > best_score {
                best = vec![from];
                best_score = score;
            } else if score == best_score {
                best.push(from);
            }
        }
        if best.len() == 1 {
            moved.from = best.remove(0);
        } else {
            let folder = path.rsplit('/').next().unwrap_or(path);
            let named: Vec<&String> = best
                .iter()
                .filter(|from| from.rsplit('/').next() == Some(folder))
                .collect();
            if named.len() == 1 {
                moved.from = named[0].clone();
            }
        }
    }
    if !moved.from.is_empty() {
        let was = git(&[
            "rev-parse",
            &format!("{parent}:{}/{STATE_FILE}", moved.from),
        ])
        .out();
        let is = git(&["rev-parse", &format!("{rev}:{path}/{STATE_FILE}")]).out();
        moved.state_kept = was == is;
    }
    moved
}

/// Follows splice <path> back from monorepo commit <upper> to its last sync.
/// Moves of the folder are followed; one that leaves the state file as it is
/// isn't a last sync.
pub fn splice_lineage(path: &str, upper: &str) -> Lineage {
    let mut path = path.to_string();
    let mut upper = upper.to_string();
    let mut moves = Vec::new();
    let mut last_sync = String::new();
    let mut before_path = String::new();
    loop {
        let commit = splice_last_sync(&path, &upper);
        if commit.is_empty() {
            break;
        }
        let moved = moved_from(&commit, &path);
        if !moved.state_kept {
            last_sync = commit;
            before_path = if moved.from.is_empty() {
                path.clone()
            } else {
                moved.from
            };
            break;
        }
        moves.push(Segment {
            path: path.clone(),
            range: format!("{commit}^1..{upper}"),
        });
        path = moved.from;
        upper = format!("{commit}^1");
    }
    let synced = if last_sync.is_empty() {
        String::new()
    } else {
        splice_config(&path, "commit", &last_sync)
    };
    Lineage {
        last_sync,
        synced,
        path,
        before_path,
        upper,
        moves,
    }
}

/// Continues the walk back to the splice's mount: the newest first-parent
/// commit whose first parent had no state file at the splice's path then, or
/// another splice's, and that's no move. Only the history from there on is
/// this splice's.
pub fn splice_lineage_to_mount(path: &str, upper: &str) -> MountLineage {
    let mut path = path.to_string();
    let mut upper = upper.to_string();
    let mut moves = Vec::new();
    let mut mount = String::new();
    if git(&["cat-file", "-e", &format!("{upper}:{path}/{STATE_FILE}")])
        .q()
        .ok()
    {
        loop {
            // Every commit the walk passes at one path has <upper>'s id: it
            // stops at the first whose parent has another.
            let id = splice_config(&path, "id", &upper);
            let spec = format!(":(top,literal){path}/{STATE_FILE}");
            let commits = git(&[
                "log",
                "--first-parent",
                "--no-show-signature",
                "--format=%H",
                &upper,
                "--",
                &spec,
            ])
            .out()
            .unwrap_or_default();
            let mut from = String::new();
            let mut at = String::new();
            for commit in commits.lines() {
                at = commit.to_string();
                if !id.is_empty()
                    && has_parent(commit)
                    && splice_config(&path, "id", &format!("{commit}^1")) == id
                {
                    continue;
                }
                from = moved_from(commit, &path).from;
                if from.is_empty() {
                    mount = commit.to_string();
                }
                break;
            }
            if from.is_empty() {
                break;
            }
            moves.push(Segment {
                path: path.clone(),
                range: format!("{at}^1..{upper}"),
            });
            path = from;
            upper = format!("{at}^1");
        }
    }
    MountLineage {
        mount,
        path,
        upper,
        moves,
    }
}

impl Repo {
    /// Folder tree <tree> without its state file. The same folder tree recurs
    /// in every commit that doesn't touch it.
    fn strip_state_tree(&mut self, tree: &str) -> Res<String> {
        if let Some(stripped) = self.content_tree_cache.get(tree) {
            return Ok(stripped.clone());
        }
        // NUL-separated throughout: a file name may contain anything but NUL.
        let entries = git(&["ls-tree", "-z", tree]).bytes().ok_or(Fail::Soft)?;
        let mut stripped: Vec<u8> = Vec::new();
        let mut found = false;
        for entry in entries.split(|&byte| byte == 0).filter(|e| !e.is_empty()) {
            let name = entry
                .iter()
                .position(|&byte| byte == b'\t')
                .map_or(entry, |tab| &entry[tab + 1..]);
            if name == STATE_FILE.as_bytes() {
                found = true;
            } else {
                stripped.extend_from_slice(entry);
                stripped.push(0);
            }
        }
        let result = if found {
            git(&["mktree", "-z"])
                .input(stripped)
                .out()
                .ok_or(Fail::Soft)?
        } else {
            tree.to_string()
        };
        self.content_tree_cache
            .insert(tree.to_string(), result.clone());
        Ok(result)
    }

    /// The tree of splice <path> in commit <rev>, without its state file, if
    /// the folder exists there.
    pub fn content_tree(&mut self, rev: &str, path: &str) -> Res<Option<String>> {
        match folder_tree(rev, path) {
            Some(tree) => Ok(Some(self.strip_state_tree(&tree)?)),
            None => Ok(None),
        }
    }

    /// The rebuild push sends for the splice at HEAD: the commit given with
    /// push --rebuilt-commit, if any, else its own.
    pub fn splice_rebuild(&mut self, path: &str) -> Res<Option<String>> {
        if let Some(given) = self.rebuild_given.get(path) {
            return Ok(Some(given.clone()));
        }
        self.rebuild_splice(path, "HEAD")
    }

    /// The upstream commit that represents the splice as of monorepo commit
    /// <rev>, or nothing if the splice has no content yet.
    pub fn rebuild_splice(&mut self, path: &str, rev: &str) -> Res<Option<String>> {
        Ok(self.rebuild_with_start(path, rev, path)?.0)
    }

    /// The commit the rebuild starts from, the splice's boundary B.
    pub fn splice_start(&mut self, path: &str, rev: &str) -> Res<Option<String>> {
        Ok(self.rebuild_with_start(path, rev, path)?.1)
    }

    /// A fetched branch of one of the splice's upstreams that has <synced> was
    /// rewritten past <commit>: the branch's reflog has it, as its fork point,
    /// but its history doesn't any more.
    fn rewritten_away(&mut self, path: &str, commit: &str, synced: &str) -> Res<bool> {
        self.require_upstream_list(path)?;
        for name in self.upstream_lists[path].clone() {
            let url = self.url_of(path, &name);
            let key = self.upstream_key(&url)?;
            if key.is_empty() {
                continue;
            }
            let refs = git(&[
                "for-each-ref",
                "--contains",
                synced,
                "--format=%(refname)",
                &format!("refs/splices/{key}/heads/"),
            ])
            .out()
            .unwrap_or_default();
            for reference in refs.lines() {
                let fork = git(&["merge-base", "--fork-point", reference, commit])
                    .q()
                    .out()
                    .unwrap_or_default();
                if fork == commit && !is_ancestor(commit, reference) {
                    return Ok(true);
                }
            }
        }
        Ok(false)
    }

    /// The rebuild and its start.
    ///
    ///   1. L is the last sync (which follows the folder through moves) and
    ///      U(L) the synced commit recorded there. If L's folder equals U(L),
    ///      the rebuild starts at U(L), and L is the start.
    ///   2. If it differs -- a pull merged local changes in, or a squash merge
    ///      mixed local edits into the commit that changed the state file -- L
    ///      is rebuilt as a commit with L's folder, whose parents are what the
    ///      rebuild had before L and U(L). Local commits that were never pushed
    ///      keep their own identity.
    ///   3. Then one commit per first-parent commit after L whose folder
    ///      differs from the one before, under the path the folder had then. A
    ///      merge in the monorepo becomes one ordinary commit.
    ///
    /// Without a synced commit (after init, before any pull), the rebuild
    /// starts at the mount, as a root commit with the folder as it was then.
    /// Nothing from before the mount is published.
    ///
    /// <name> is the splice's path in HEAD, for its upstreams and messages,
    /// where step 2 rebuilds it at the path it had before a move.
    fn rebuild_with_start(
        &mut self,
        path: &str,
        rev: &str,
        name: &str,
    ) -> Res<(Option<String>, Option<String>)> {
        let lineage = splice_lineage(path, rev);
        let mut last_sync = lineage.last_sync;
        let mut synced = lineage.synced;
        let mut at = lineage.path;
        let mut before_path = lineage.before_path;
        let mut upper = lineage.upper;
        let mut moves = lineage.moves;
        if !last_sync.is_empty() {
            refuse_shallow_start(name, &last_sync)?;
        }

        // A nested splice's history up to the last sync of a splice above it
        // is in that splice's upstream: a clone or pull of the splice above
        // squashed it into one commit here. So up to there, it's rebuilt from
        // the upstream's history, at the synced commit of the splice above,
        // and that rebuild stands in for the synced commit. Of the splices
        // above, the one with the newest last sync covers the most history; on
        // a tie, the outermost. Only where the upstream above has the same
        // splice at the path: it may have replaced it with another.
        let mut seg_paths: Vec<String> = moves.iter().map(|m| m.path.clone()).collect();
        seg_paths.push(at.clone());
        let mut seg_uppers: Vec<String> = moves
            .iter()
            .map(|m| upper_of(&m.range).to_string())
            .collect();
        seg_uppers.push(upper.clone());
        let mut seg_lowers: Vec<String> = moves
            .iter()
            .map(|m| lower_of(&m.range).to_string())
            .collect();
        seg_lowers.push(String::new());
        let mut best: Option<(String, String, String, usize)> = None;
        if !last_sync.is_empty() {
            for k in 0..seg_paths.len() {
                let mut dir = seg_paths[k].clone();
                while let Some(above) = splice_above_in(&seg_uppers[k], &dir) {
                    dir = above.clone();
                    let above_lineage = splice_lineage(&above, &seg_uppers[k]);
                    let (above_last, above_synced) =
                        (above_lineage.last_sync, above_lineage.synced);
                    if above_last.is_empty()
                        || above_synced.is_empty()
                        || !commit_here(&above_synced)
                        || !is_ancestor(&last_sync, &above_last)
                    {
                        continue;
                    }
                    // On a newer path, only a last sync since the move to it.
                    if !seg_lowers[k].is_empty() && is_ancestor(&above_last, &seg_lowers[k]) {
                        continue;
                    }
                    if let Some((_, best_last, _, _)) = &best {
                        if !is_ancestor(best_last, &above_last) {
                            continue;
                        }
                    }
                    let inner = seg_paths[k]
                        .strip_prefix(&format!("{above}/"))
                        .unwrap_or(&seg_paths[k]);
                    if splice_config(inner, "id", &above_synced)
                        != splice_config(&seg_paths[k], "id", &seg_uppers[k])
                    {
                        continue;
                    }
                    best = Some((above, above_last, above_synced, k));
                }
                if best.is_some() {
                    break;
                }
            }
        }
        let mut from_above = false;
        if let Some((best_above, best_last, best_synced, k)) = best {
            let inner = seg_paths[k]
                .strip_prefix(&format!("{best_above}/"))
                .unwrap_or(&seg_paths[k])
                .to_string();
            if let Some(rebuilt) = self.rebuild_splice(&inner, &best_synced)? {
                from_above = true;
                // A newer last sync above: the splice had this path in its
                // first parent, or the one before, if the last sync is the move
                // to it.
                if best_last != last_sync {
                    before_path = seg_paths[k].clone();
                    if !seg_lowers[k].is_empty()
                        && git(&["rev-parse", &format!("{best_last}^1")]).out()
                            == git(&["rev-parse", &seg_lowers[k]]).out()
                    {
                        before_path = seg_paths[k + 1].clone();
                    }
                }
                last_sync = best_last;
                synced = rebuilt;
                // The walk starts on that path; only the moves after it are left.
                at = seg_paths[k].clone();
                upper = seg_uppers[k].clone();
                moves.truncate(k);
            }
        }

        if !synced.is_empty() && !commit_here(&synced) {
            // push --force: the upstream no longer has the synced commit, and
            // the monorepo's side replaces its history anyway.
            if !self.rebuild_without_synced {
                return fail(format!(
                    "{name}: synced commit {} isn't available locally -- run 'git splice fetch {name}'",
                    short(&synced)
                ));
            }
            synced.clear();
        }

        let mut prev: Option<String> = None;
        let start: Option<String>;
        let range: String;
        if !synced.is_empty() {
            let mut rebuild_start = Some(last_sync.clone());
            prev = Some(synced.clone());
            let prev_tree = tree_of(&synced).ok_or(Fail::Soft)?;
            let tree = self.content_tree(&last_sync, &at)?;
            // With the history from above, L's folder may equal it while the
            // monorepo's history before L has commits it lacks. They're joined
            // all the same. So is a move that changed the state file.
            if let Some(tree) =
                tree.filter(|tree| *tree != prev_tree || from_above || before_path != at)
            {
                let mut before = None;
                let mut before_start = None;
                let first_parent = format!("{last_sync}^1");
                // Unless L is the mount: what came before isn't this splice's.
                if has_parent(&last_sync)
                    && same_splice(&before_path, &first_parent, &last_sync, &at)
                {
                    let result = self.rebuild_with_start(&before_path, &first_parent, name)?;
                    before = result.0;
                    before_start = result.1;
                }
                let parents: Vec<String>;
                match &before {
                    Some(earlier) if !is_ancestor(earlier, &synced) => {
                        if is_ancestor(&synced, earlier) {
                            // What came before already contains U(L), e.g. L
                            // only changed the state file: continue from there.
                            parents = vec![earlier.clone()];
                            rebuild_start = before_start;
                        } else {
                            // The synced commit before L isn't in U(L)'s
                            // history. If a fetched branch dropped it, the
                            // upstream rewrote its branch, and L mixed changes
                            // of its own into the pull. Joining both sides
                            // would publish the rewritten-away commits again;
                            // merge and pull only compare with the rebuild, and
                            // their pull is the way out.
                            let previous = splice_config(&before_path, "commit", &first_parent);
                            if !self.joins_rewritten
                                && !previous.is_empty()
                                && commit_here(&previous)
                                && !is_ancestor(&previous, &synced)
                                && self.rewritten_away(name, &previous, &synced)?
                            {
                                return fail(format!(
                                    "{name}: {} records {}, which the upstream rewrote from {}, and has changes of its own -- commit the folder's changes on top of the upstream branch yourself, push them there, then pull: the rebuild would publish the rewritten-away commits again",
                                    short(&last_sync),
                                    short(&synced),
                                    short(&previous)
                                ));
                            }
                            // A pull merged a divergence: join both sides.
                            parents = vec![earlier.clone(), synced.clone()];
                            rebuild_start = before_start;
                        }
                    }
                    _ => {
                        // Nothing unpushed before L: L's changes go on top of
                        // U(L). Where L's folder isn't U(L), L itself is
                        // copied, so the rebuild starts where the one before
                        // L did.
                        parents = vec![synced.clone()];
                        if tree != prev_tree && before_start.is_some() {
                            rebuild_start = before_start;
                        }
                    }
                }
                prev = if parents.len() == 1
                    && Some(tree.as_str()) == tree_of(&parents[0]).as_deref()
                {
                    Some(parents[0].clone())
                } else {
                    Some(copy_commit(&last_sync, &tree, &parents)?)
                };
            }
            range = format!("{last_sync}..{upper}");
            start = rebuild_start;
        } else {
            let mount = splice_lineage_to_mount(&at, &upper);
            moves.extend(mount.moves);
            at = mount.path;
            upper = mount.upper;
            if mount.mount.is_empty() {
                return Ok((None, None));
            }
            refuse_shallow_start(name, &mount.mount)?;
            range = if has_parent(&mount.mount) {
                format!("{}^1..{upper}", mount.mount)
            } else {
                upper.clone()
            };
            start = Some(mount.mount);
        }

        let mut prev = self.rebuild_walk(&at, prev, &range)?;
        for segment in moves.iter().rev() {
            prev = self.rebuild_walk(&segment.path, prev, &segment.range)?;
        }
        Ok((prev, start))
    }

    /// The rebuild of the splice along <range>, on top of upstream commit
    /// <start> (nothing: a new root): one commit per first-parent commit whose
    /// folder differs from the one before. A merge in the monorepo becomes one
    /// ordinary commit.
    fn rebuild_walk(
        &mut self,
        path: &str,
        start: Option<String>,
        range: &str,
    ) -> Res<Option<String>> {
        let mut prev = start;
        let mut prev_tree = match &prev {
            Some(commit) => Some(tree_of(commit).ok_or(Fail::Soft)?),
            None => None,
        };
        // Every field ends with a NUL; tformat adds a newline after each
        // commit, which then starts the next hash.
        let format = format!("--pretty=tformat:%H%x00{COPY_FORMAT}%x00");
        let spec = format!(":(top,literal){path}");
        let output = encoded_git(&[
            "log",
            "--reverse",
            "--first-parent",
            "--no-show-signature",
            &format,
            range,
            "--",
            &spec,
        ])
        .bytes()
        .ok_or(Fail::Soft)?;
        let fields: Vec<&[u8]> = output.split(|&byte| byte == 0).collect();
        let commits: Vec<&[&[u8]]> = fields.chunks_exact(8).collect();
        if commits.is_empty() {
            return Ok(prev);
        }
        let hash_of = |commit: &[&[u8]]| {
            let hash = commit[0].strip_prefix(b"\n").unwrap_or(commit[0]);
            String::from_utf8_lossy(hash).into_owned()
        };
        let queries: String = commits
            .iter()
            .map(|commit| format!("{}:{path}\n", hash_of(commit)))
            .collect();
        let objects = git(&["cat-file", "--batch-check=%(objectname) %(objecttype)"])
            .input(queries)
            .out()
            .ok_or(Fail::Soft)?;
        for (commit, object) in commits.iter().zip(objects.lines()) {
            let mut words = object.split(' ');
            let (Some(folder), Some("tree")) = (words.next(), words.next()) else {
                continue;
            };
            let tree = self.strip_state_tree(folder)?;
            if Some(&tree) == prev_tree.as_ref() {
                continue;
            }
            let parents: Vec<String> = prev.iter().cloned().collect();
            let copy = write_copy(
                &Copied {
                    author: commit[1],
                    email: commit[2],
                    date: commit[3],
                    committer: commit[4],
                    committer_email: commit[5],
                    committer_date: commit[6],
                    message: commit[7],
                },
                &tree,
                &parents,
            )?;
            prev = Some(copy);
            prev_tree = Some(tree);
        }
        Ok(prev)
    }
}
