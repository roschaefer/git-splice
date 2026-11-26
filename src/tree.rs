//! The work an operation did and still does for each splice, as a promise
//! is pending or settled: for a tree drawing, or a test, to show next to
//! each splice.

use serde::{Serialize, Serializer};
use std::collections::HashMap;

/// A step an operation still has to take for a splice.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Step {
    Fetch,
    /// Merges go top-down: a splice's waits for the one around it.
    Merge,
}

/// What an operation did or still does for a splice, as it decided it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "task", rename_all = "lowercase")]
pub enum Task {
    Pending {
        step: Step,
    },
    Done,
    /// Its merge stopped in a conflict.
    Conflict,
    /// Not merged: it waits on the splice at this path, which stopped in a
    /// conflict or failed.
    Blocked {
        by: String,
    },
    Failed,
    /// The pull above removed it, or it isn't a splice any more.
    Removed,
    /// A copy of the splice at this path, which it's inside: not merged.
    Copy {
        of: String,
    },
}

/// An operation's work per splice, and its next step beyond them.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize)]
pub struct Tasks {
    /// Each splice's task, top-down.
    #[serde(rename = "splices", serialize_with = "path_and_task")]
    pub per_splice: Vec<(String, Task)>,
    /// The next step that belongs to no single splice, e.g. "fold".
    pub next: Option<&'static str>,
}

/// Each splice as an object: its path, and its task's fields.
fn path_and_task<S: Serializer>(per_splice: &[(String, Task)], to: S) -> Result<S::Ok, S::Error> {
    #[derive(Serialize)]
    struct Entry<'a> {
        path: &'a str,
        #[serde(flatten)]
        task: &'a Task,
    }
    to.collect_seq(per_splice.iter().map(|(path, task)| Entry { path, task }))
}

impl Tasks {
    /// Each splice's task as text, by path, naming other splices by their
    /// path: "pending: merge, after vendor/a/" for a merge that waits on the
    /// splice around it.
    pub fn notes(&self) -> HashMap<String, String> {
        let pending_merge = |path: &str| {
            self.per_splice
                .iter()
                .any(|(p, task)| p == path && *task == Task::Pending { step: Step::Merge })
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
                    Task::Pending { step: Step::Fetch } => "pending: fetch".to_string(),
                    Task::Pending { step: Step::Merge } => {
                        match around(path).filter(|a| pending_merge(a)) {
                            Some(above) => format!("pending: merge, after {above}/"),
                            None => "pending: merge".to_string(),
                        }
                    }
                    Task::Done => "done".to_string(),
                    Task::Conflict => "conflict".to_string(),
                    Task::Blocked { by } => format!("blocked by {by}/"),
                    Task::Failed => "failed".to_string(),
                    Task::Removed => "removed".to_string(),
                    Task::Copy { of } => format!("copy of {of}/"),
                };
                (path.clone(), note)
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tasks_as_json_name_each_task_and_what_it_waits_on() {
        let tasks = Tasks {
            per_splice: vec![
                ("a".into(), Task::Done),
                ("a/b".into(), Task::Pending { step: Step::Merge }),
                ("a/c".into(), Task::Blocked { by: "a/b".into() }),
                ("a/a".into(), Task::Copy { of: "a".into() }),
            ],
            next: Some("fold"),
        };
        assert_eq!(
            serde_json::to_string(&tasks).unwrap(),
            concat!(
                r#"{"splices":[{"path":"a","task":"done"},"#,
                r#"{"path":"a/b","task":"pending","step":"merge"},"#,
                r#"{"path":"a/c","task":"blocked","by":"a/b"},"#,
                r#"{"path":"a/a","task":"copy","of":"a"}],"next":"fold"}"#
            )
        );
        assert_eq!(
            serde_json::to_string(&Tasks::default()).unwrap(),
            r#"{"splices":[],"next":null}"#
        );
    }
}
