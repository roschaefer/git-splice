//! The rebuilt commits of earlier runs, kept in the file `splice-rebuilds` in
//! the repository's common Git directory, so a rebuild only walks the commits
//! added since (#245).
//!
//! A step of the rebuild's walk is a pure function of its inputs, all of them
//! commit ids: the splice's path, the upstream commit the walk starts on, the
//! commit the walk's range starts after, and the monorepo commit it has
//! reached. Those are the key; the rebuilt commit and its tree after that step
//! are the value. Keys never change meaning, so nothing needs invalidating.
//! Losing the file costs time only: each step is computed again.

use crate::util::*;
use std::collections::HashMap;
use std::io::Write;
use std::path::PathBuf;

/// The file's first line. A file without it, from another format, is
/// started over.
const HEADER: &[u8] = b"git-splice rebuilds 1\n";
/// Started over past this many steps, so the file can't grow without bound.
const MAX_STEPS: usize = 200_000;
const FIELDS: usize = 6;

#[derive(Clone, Hash, PartialEq, Eq)]
pub(crate) struct Key {
    pub path: String,
    pub start: String,
    pub lower: String,
    pub commit: String,
}

#[derive(Clone)]
pub(crate) struct Step {
    pub copy: String,
    pub tree: String,
}

#[derive(Default)]
pub(crate) struct RebuildCache {
    file: Option<PathBuf>,
    steps: HashMap<Key, Step>,
    /// The file must be written again from the start: it's missing, or what
    /// it has can't be appended to.
    rewrite: bool,
    added: Vec<u8>,
}

/// A full object id, SHA-1 or SHA-256.
pub(crate) fn is_id(text: &str) -> bool {
    (text.len() == 40 || text.len() == 64)
        && text
            .bytes()
            .all(|byte| matches!(byte, b'0'..=b'9' | b'a'..=b'f'))
}

/// A walk's range starts after a commit named by an id, or by its first
/// parent; or it has no start. Anything else could name another commit later.
pub(crate) fn is_fixed_lower(lower: &str) -> bool {
    lower.is_empty() || is_id(lower.strip_suffix("^1").unwrap_or(lower))
}

fn record(key: &Key, step: &Step) -> Vec<u8> {
    let mut bytes = Vec::new();
    for field in [
        &key.path,
        &key.start,
        &key.lower,
        &key.commit,
        &step.copy,
        &step.tree,
    ] {
        bytes.extend_from_slice(field.as_bytes());
        bytes.push(0);
    }
    bytes
}

/// The steps in <data>, NUL-separated records of six fields after the header.
/// A record cut off at the end, by a write that didn't finish, is left out;
/// None if anything else is wrong.
fn parse(data: &[u8]) -> Option<(HashMap<Key, Step>, bool)> {
    let body = data.strip_prefix(HEADER)?;
    let mut fields: Vec<&[u8]> = body.split(|&byte| byte == 0).collect();
    // What follows the last NUL: nothing, or a field cut off.
    let mut complete = fields.pop().is_some_and(<[u8]>::is_empty);
    let whole = fields.len() - fields.len() % FIELDS;
    complete &= whole == fields.len();
    let mut steps = HashMap::new();
    for chunk in fields[..whole].chunks_exact(FIELDS) {
        let text: Vec<&str> = chunk
            .iter()
            .map(|field| std::str::from_utf8(field).ok())
            .collect::<Option<_>>()?;
        let [path, start, lower, commit, copy, tree] = text[..] else {
            return None;
        };
        if path.is_empty()
            || !(start.is_empty() || is_id(start))
            || !is_fixed_lower(lower)
            || ![commit, copy, tree].into_iter().all(is_id)
        {
            return None;
        }
        steps.insert(
            Key {
                path: path.to_string(),
                start: start.to_string(),
                lower: lower.to_string(),
                commit: commit.to_string(),
            },
            Step {
                copy: copy.to_string(),
                tree: tree.to_string(),
            },
        );
    }
    Some((steps, complete))
}

impl RebuildCache {
    pub(crate) fn load() -> Self {
        let dir = git(&["rev-parse", "--path-format=absolute", "--git-common-dir"])
            .q()
            .bytes()
            .unwrap_or_default();
        let Ok(dir) = path_from_output(dir) else {
            return Self::default();
        };
        if dir.as_os_str().is_empty() {
            return Self::default();
        }
        let file = dir.join("splice-rebuilds");
        let parsed = std::fs::read(&file).ok().and_then(|data| parse(&data));
        let (steps, complete) = match parsed {
            Some((steps, complete)) if steps.len() <= MAX_STEPS => (steps, complete),
            _ => (HashMap::new(), false),
        };
        Self {
            file: Some(file),
            steps,
            rewrite: !complete,
            added: Vec::new(),
        }
    }

    pub(crate) fn get(&self, key: &Key) -> Option<&Step> {
        self.steps.get(key)
    }

    pub(crate) fn insert(&mut self, key: Key, step: Step) {
        if self.file.is_none() {
            return;
        }
        self.added.extend(record(&key, &step));
        self.steps.insert(key, step);
    }

    /// Writes the steps added since the last save. Failing to is no error:
    /// the next run computes them again.
    pub(crate) fn save(&mut self) {
        let Some(file) = &self.file else { return };
        if self.added.is_empty() && !self.rewrite {
            return;
        }
        if self.rewrite {
            let mut bytes = HEADER.to_vec();
            for (key, step) in &self.steps {
                bytes.extend(record(key, step));
            }
            let temporary = file.with_extension(format!("{}.tmp", std::process::id()));
            if std::fs::write(&temporary, bytes).is_ok()
                && std::fs::rename(&temporary, file).is_ok()
            {
                self.rewrite = false;
            } else {
                let _ = std::fs::remove_file(&temporary);
            }
        } else if let Ok(mut out) = std::fs::OpenOptions::new().append(true).open(file) {
            // One write, so another process appending at the same time
            // doesn't interleave inside a record.
            let _ = out.write_all(&self.added);
        }
        self.added.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const A: &str = "1111111111111111111111111111111111111111";
    const B: &str = "2222222222222222222222222222222222222222";

    fn key(n: usize) -> Key {
        Key {
            path: "vendor/a b".into(),
            start: A.into(),
            lower: format!("{B}^1"),
            commit: format!("{n:040x}"),
        }
    }

    fn file_with(steps: usize) -> Vec<u8> {
        let mut data = HEADER.to_vec();
        for n in 0..steps {
            data.extend(record(
                &key(n),
                &Step {
                    copy: A.into(),
                    tree: B.into(),
                },
            ));
        }
        data
    }

    #[test]
    fn a_written_step_reads_back() {
        let (steps, complete) = parse(&file_with(1)).unwrap();
        assert!(complete);
        assert_eq!(steps[&key(0)].copy, A);
    }

    #[test]
    fn a_step_cut_off_at_the_end_is_left_out_and_the_file_rewritten() {
        let data = file_with(2);
        for cut in 1..60 {
            let (steps, complete) = parse(&data[..data.len() - cut]).unwrap();
            assert!(!complete, "cut {cut}");
            assert_eq!(steps.len(), 1, "cut {cut}");
        }
    }

    #[test]
    fn a_file_without_the_header_or_with_garbage_is_ignored() {
        assert!(parse(b"something else\n").is_none());
        let mut data = file_with(1);
        data.extend(b"not\0an\0id\0at\0all\0!\0");
        assert!(parse(&data).is_none());
    }

    #[test]
    fn only_ids_and_their_first_parents_are_fixed_lowers() {
        assert!(is_fixed_lower(""));
        assert!(is_fixed_lower(A));
        assert!(is_fixed_lower(&format!("{A}^1")));
        assert!(!is_fixed_lower("HEAD"));
        assert!(!is_fixed_lower(&format!("{A}^2")));
        assert!(!is_fixed_lower(&A[..7]));
    }
}
