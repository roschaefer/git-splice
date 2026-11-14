//! The work an operation did and still does for each splice, as a promise
//! is pending or settled: for a tree drawing, or a test, to show next to
//! each splice.

use std::collections::HashMap;

/// A step an operation still has to take for a splice.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Step {
    Fetch,
    /// Merges go top-down: a splice's waits for the one around it.
    Merge,
}

/// What an operation did or still does for a splice, as it decided it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Task {
    Pending(Step),
    Done,
    /// Its merge stopped in a conflict.
    Conflict,
    /// Not merged: it waits on the splice at this path, which stopped in a
    /// conflict or failed.
    Blocked(String),
    Failed,
    /// The pull above removed it, or it isn't a splice any more.
    Removed,
    /// A copy of the splice at this path, which it's inside: not merged.
    Copy(String),
}

/// An operation's work per splice, and its next step beyond them.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Tasks {
    /// Each splice's task, top-down.
    pub per_splice: Vec<(String, Task)>,
    /// The next step that belongs to no single splice, e.g. "fold".
    pub next: Option<&'static str>,
}

impl Tasks {
    /// Each splice's task as text, by path, naming other splices by their
    /// path: "pending: merge, after vendor/a/" for a merge that waits on the
    /// splice around it.
    pub fn notes(&self) -> HashMap<String, String> {
        let pending_merge = |path: &str| {
            self.per_splice
                .iter()
                .any(|(p, task)| p == path && *task == Task::Pending(Step::Merge))
        };
        let around = |path: &str| {
            self.per_splice
                .iter()
                .map(|(p, _)| p.as_str())
                .filter(|p| path.starts_with(&format!("{p}/")))
                .max_by_key(|p| p.len())
        };
        self.per_splice
            .iter()
            .map(|(path, task)| {
                let note = match task {
                    Task::Pending(Step::Fetch) => "pending: fetch".to_string(),
                    Task::Pending(Step::Merge) => match around(path).filter(|a| pending_merge(a)) {
                        Some(above) => format!("pending: merge, after {above}/"),
                        None => "pending: merge".to_string(),
                    },
                    Task::Done => "done".to_string(),
                    Task::Conflict => "conflict".to_string(),
                    Task::Blocked(on) => format!("blocked by {on}/"),
                    Task::Failed => "failed".to_string(),
                    Task::Removed => "removed".to_string(),
                    Task::Copy(of) => format!("copy of {of}/"),
                };
                (path.clone(), note)
            })
            .collect()
    }
}
