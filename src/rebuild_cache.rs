//! Where earlier runs' rebuilds ended, kept in the file `splice-rebuilds` in
//! the repository's common Git directory, so a rebuild only walks the commits
//! added since (#245).
//!
//! A step of the rebuild's walk is a pure function of its inputs, all of them
//! commit ids: the splice's path, the upstream commit the walk starts on, the
//! commit the walk's range starts after, and the monorepo commit it has
//! reached. Those are the key; the rebuilt commit after that step is the
//! value. Keys never change meaning, so nothing needs invalidating. Only a
//! walk's last step is kept, which a later walk on the same branch goes on
//! from. Losing the file costs time only: each step is computed again.

use crate::util::*;
use std::collections::HashMap;
use std::path::PathBuf;

/// The file's first line. A file without it, from another format, is
/// started over.
const HEADER: &[u8] = b"git-splice rebuilds 2\n";
/// Started over past this many steps, so the file can't grow without bound.
const MAX_STEPS: usize = 10_000;
const FIELDS: usize = 5;

#[derive(Clone, Hash, PartialEq, Eq)]
pub(crate) struct Key {
    pub path: String,
    pub start: String,
    pub lower: String,
    pub commit: String,
}

#[derive(Default)]
pub(crate) struct RebuildCache {
    file: Option<PathBuf>,
    /// The rebuilt commit of each step.
    steps: HashMap<Key, String>,
    changed: bool,
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

/// The steps in <data>, NUL-separated records of five fields after the
/// header; None if it isn't one. A wrong key never matches, and a wrong
/// rebuilt commit isn't found, which costs a full walk.
fn parse(data: &[u8]) -> Option<HashMap<Key, String>> {
    let text = std::str::from_utf8(data.strip_prefix(HEADER)?).ok()?;
    let fields: Vec<&str> = text.strip_suffix('\0')?.split('\0').collect();
    if !fields.len().is_multiple_of(FIELDS) {
        return None;
    }
    Some(
        fields
            .chunks_exact(FIELDS)
            .map(|record| {
                let key = Key {
                    path: record[0].to_string(),
                    start: record[1].to_string(),
                    lower: record[2].to_string(),
                    commit: record[3].to_string(),
                };
                (key, record[4].to_string())
            })
            .collect(),
    )
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
        let steps = std::fs::read(&file)
            .ok()
            .and_then(|data| parse(&data))
            .filter(|steps| steps.len() <= MAX_STEPS)
            .unwrap_or_default();
        Self {
            file: Some(file),
            steps,
            changed: false,
        }
    }

    pub(crate) fn get(&self, key: &Key) -> Option<&String> {
        self.steps.get(key)
    }

    pub(crate) fn insert(&mut self, key: Key, rebuilt: String) {
        if self.file.is_some() {
            self.steps.insert(key, rebuilt);
            self.changed = true;
        }
    }

    /// Writes the file again, whole, if a step was added. Failing to is no
    /// error: the next run computes the steps again. Two runs writing at once
    /// keep the steps of the one that renames last.
    pub(crate) fn save(&mut self) {
        let Some(file) = &self.file else { return };
        if !self.changed {
            return;
        }
        let mut bytes = HEADER.to_vec();
        for (key, rebuilt) in &self.steps {
            for field in [&key.path, &key.start, &key.lower, &key.commit, rebuilt] {
                bytes.extend_from_slice(field.as_bytes());
                bytes.push(0);
            }
        }
        let temporary = file.with_extension(format!("{}.tmp", std::process::id()));
        if std::fs::write(&temporary, bytes).is_err() || std::fs::rename(&temporary, file).is_err()
        {
            let _ = std::fs::remove_file(&temporary);
        }
        self.changed = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const A: &str = "1111111111111111111111111111111111111111";
    const B: &str = "2222222222222222222222222222222222222222";

    fn key() -> Key {
        Key {
            path: "vendor/a b".into(),
            start: A.into(),
            lower: format!("{B}^1"),
            commit: B.into(),
        }
    }

    fn file() -> Vec<u8> {
        let mut data = HEADER.to_vec();
        for field in ["vendor/a b", A, &format!("{B}^1"), B, A] {
            data.extend_from_slice(field.as_bytes());
            data.push(0);
        }
        data
    }

    #[test]
    fn a_written_step_reads_back() {
        assert_eq!(parse(&file()).unwrap()[&key()], A);
    }

    #[test]
    fn a_file_cut_off_or_without_the_header_is_ignored() {
        let data = file();
        for cut in 1..data.len() - HEADER.len() {
            assert!(parse(&data[..data.len() - cut]).is_none(), "cut {cut}");
        }
        assert!(parse(b"something else\n").is_none());
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
