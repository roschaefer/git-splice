//! Where earlier runs' rebuilds ended, kept in the file `splice-rebuilds` in
//! the repository's common Git directory, so a rebuild only walks the commits
//! added since (#245).
//!
//! A step of the rebuild's walk is a pure function of its inputs, all of them
//! commit ids: the splice's path, the upstream commit the walk starts on, the
//! commit the walk's range starts after, and the monorepo commit it has
//! reached. Those are the key; the rebuilt commit after that step is the
//! value. Keys never change meaning, so nothing needs invalidating, except
//! where Git reads some commits as others, through replace refs or grafts,
//! or hides parents, in a shallow clone: then nothing is remembered, as Git
//! doesn't use its commit-graph file then either. Only a walk's last step is
//! kept, which a later walk on the same branch goes on from. Losing the file
//! costs time only: each step is computed again.

use crate::util::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// The file's format. A file of another one is started over.
const VERSION: u32 = 3;
/// Started over past this many steps, so the file can't grow without bound.
const MAX_STEPS: usize = 10_000;

#[derive(Hash, PartialEq, Eq, Serialize, Deserialize)]
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

/// The file, in JSON: each step as a pair of its key and its rebuilt commit,
/// since a JSON object's keys are strings.
#[derive(Serialize, Deserialize)]
struct File<Steps> {
    version: u32,
    steps: Steps,
}

/// The steps in <data>; None if it isn't such a file. A wrong key never
/// matches, and a wrong rebuilt commit isn't found, which costs a full walk.
fn parse(data: &[u8]) -> Option<HashMap<Key, String>> {
    let file: File<Vec<(Key, String)>> = serde_json::from_slice(data).ok()?;
    (file.version == VERSION).then(|| file.steps.into_iter().collect())
}

fn write(steps: &HashMap<Key, String>) -> Option<Vec<u8>> {
    let steps: Vec<_> = steps.iter().collect();
    serde_json::to_vec(&File {
        version: VERSION,
        steps,
    })
    .ok()
}

/// Whether Git may read a commit other than as it was made under its id:
/// through replace refs, grafts, or a shallow clone's cut-off parents.
/// Unsure counts as yes.
fn commits_altered() -> bool {
    let replaced = git(&["replace", "--list"])
        .q()
        .out()
        .is_none_or(|refs| !refs.is_empty());
    // --git-path gives GIT_GRAFT_FILE where it's set.
    let grafts = git(&[
        "rev-parse",
        "--path-format=absolute",
        "--git-path",
        "info/grafts",
    ])
    .q()
    .bytes()
    .and_then(|path| path_from_output(path).ok());
    let shallow = git(&["rev-parse", "--is-shallow-repository"])
        .q()
        .out()
        .is_none_or(|shallow| shallow != "false");
    replaced || shallow || grafts.is_none_or(|file| file.exists())
}

impl RebuildCache {
    pub(crate) fn load() -> Self {
        if commits_altered() {
            return Self::default();
        }
        let Some(dir) = git(&["rev-parse", "--path-format=absolute", "--git-common-dir"])
            .q()
            .bytes()
            .and_then(|dir| path_from_output(dir).ok())
        else {
            return Self::default();
        };
        let file = dir.join("splice-rebuilds");
        let steps = std::fs::read(&file)
            .ok()
            .and_then(|data| parse(&data))
            .filter(|steps| steps.len() <= MAX_STEPS)
            .unwrap_or_default();
        Self {
            file: Some(file),
            steps,
        }
    }

    pub(crate) fn get(&self, key: &Key) -> Option<&String> {
        self.steps.get(key)
    }

    /// Adds the step and writes the file again, whole. Failing to is no
    /// error: the next run computes the steps again. Two runs writing at once
    /// keep the steps of the one that renames last.
    pub(crate) fn remember(&mut self, key: Key, rebuilt: String) {
        let Some(file) = &self.file else { return };
        self.steps.insert(key, rebuilt);
        let Some(bytes) = write(&self.steps) else {
            return;
        };
        let temporary = file.with_extension(format!("{}.tmp", std::process::id()));
        if std::fs::write(&temporary, bytes).is_err() || std::fs::rename(&temporary, file).is_err()
        {
            let _ = std::fs::remove_file(&temporary);
        }
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
        write(&HashMap::from([(key(), A.to_string())])).unwrap()
    }

    #[test]
    fn a_written_step_reads_back() {
        assert_eq!(parse(&file()).unwrap()[&key()], A);
    }

    #[test]
    fn a_file_cut_off_of_another_version_or_not_json_is_ignored() {
        let data = file();
        for cut in 1..data.len() {
            assert!(parse(&data[..data.len() - cut]).is_none(), "cut {cut}");
        }
        let other = String::from_utf8(data)
            .unwrap()
            .replace(&format!("\"version\":{VERSION}"), "\"version\":2");
        assert!(parse(other.as_bytes()).is_none());
        assert!(parse(b"git-splice rebuilds 2\n").is_none());
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
