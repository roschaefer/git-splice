//! The work an operation did and still does for each splice, as a promise
//! is pending or settled: for a tree drawing, or a test, to show next to
//! each splice.

use crate::util::{json_array, json_object, json_string};
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
    /// The tasks as JSON: an object with each splice's task, top-down, and
    /// the next step beyond them, or null.
    pub fn to_json(&self) -> String {
        let splices: Vec<String> = self
            .per_splice
            .iter()
            .map(|(path, task)| {
                let (name, detail) = match task {
                    Task::Pending(Step::Fetch) => ("pending", Some(("step", "fetch"))),
                    Task::Pending(Step::Merge) => ("pending", Some(("step", "merge"))),
                    Task::Done => ("done", None),
                    Task::Conflict => ("conflict", None),
                    Task::Blocked(by) => ("blocked", Some(("by", by.as_str()))),
                    Task::Failed => ("failed", None),
                    Task::Removed => ("removed", None),
                    Task::Copy(of) => ("copy", Some(("of", of.as_str()))),
                };
                let mut fields = vec![("path", json_string(path)), ("task", json_string(name))];
                fields.extend(detail.map(|(key, value)| (key, json_string(value))));
                json_object(&fields)
            })
            .collect();
        let next = self.next.map_or("null".to_string(), json_string);
        json_object(&[("splices", json_array(splices)), ("next", next)])
    }

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tasks_as_json_name_each_task_and_what_it_waits_on() {
        let tasks = Tasks {
            per_splice: vec![
                ("a".into(), Task::Done),
                ("a/b".into(), Task::Pending(Step::Merge)),
                ("a/c".into(), Task::Blocked("a/b".into())),
                ("a/a".into(), Task::Copy("a".into())),
            ],
            next: Some("fold"),
        };
        assert_eq!(
            tasks.to_json(),
            concat!(
                r#"{"splices":[{"path":"a","task":"done"},"#,
                r#"{"path":"a/b","task":"pending","step":"merge"},"#,
                r#"{"path":"a/c","task":"blocked","by":"a/b"},"#,
                r#"{"path":"a/a","task":"copy","of":"a"}],"next":"fold"}"#
            )
        );
        assert_eq!(Tasks::default().to_json(), r#"{"splices":[],"next":null}"#);
    }
}
