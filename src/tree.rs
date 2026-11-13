//! The work an operation did and still does for each splice, as a promise
//! is pending or settled: for a tree drawing, or a test, to show next to
//! each splice.

/// What an operation did or still does for a splice.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Task {
    Done,
    /// The step that is still to come, e.g. "merge".
    Pending(&'static str),
    Failed,
    Conflict,
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
    /// Each splice's task as text, by path: "pending: merge, after b/" for a
    /// merge that waits on the splice around it, as merges go top-down.
    pub fn notes(&self) -> std::collections::HashMap<String, String> {
        let pending = |path: &str| {
            self.per_splice
                .iter()
                .any(|(p, task)| p == path && matches!(task, Task::Pending(_)))
        };
        let around = |path: &str| {
            self.per_splice
                .iter()
                .map(|(p, _)| p.as_str())
                .filter(|p| path.starts_with(&format!("{p}/")))
                .max_by_key(|p| p.len())
                .map(str::to_string)
        };
        self.per_splice
            .iter()
            .map(|(path, task)| {
                let mut note = match task {
                    Task::Done => "done".to_string(),
                    Task::Failed => "failed".to_string(),
                    Task::Conflict => "conflict".to_string(),
                    Task::Pending(step) => format!("pending: {step}"),
                };
                if *task == Task::Pending("merge") {
                    if let Some(above) = around(path).filter(|a| pending(a)) {
                        let name = match around(&above) {
                            Some(top) => above[top.len() + 1..].to_string(),
                            None => above.clone(),
                        };
                        note.push_str(&format!(", after {name}/"));
                    }
                }
                (path.clone(), note)
            })
            .collect()
    }
}
