//! The splice tree as a table: each splice's boundary B, synced commit U,
//! rebuild R and upstream branch T at HEAD, and the work an operation still
//! has for it. The same picture as a tree drawing, as text.

use crate::repo::*;
use crate::util::*;

/// What an operation did or still does for a splice.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Task {
    Done,
    Pending(&'static str),
    Failed,
    Conflict,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Node {
    pub path: String,
    /// B: the monorepo commit the rebuild starts at.
    pub boundary: Option<String>,
    /// U: the synced commit HEAD's .splice records.
    pub synced: String,
    /// R: the rebuild push would send.
    pub rebuild: Option<String>,
    /// T: the fetched upstream branch, or pin, the splice follows.
    pub target: Option<String>,
    pub task: Option<Task>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SpliceTree {
    pub head: String,
    /// Splices top-down, a parent before the ones inside it.
    pub nodes: Vec<Node>,
    /// The operation's next step that belongs to no single splice.
    pub next: Option<&'static str>,
}

/// An operation's work per splice, and its next step beyond them.
#[derive(Default)]
pub(crate) struct Tasks {
    pub per_splice: Vec<(String, Task)>,
    pub next: Option<&'static str>,
}

impl Repo<'_> {
    pub(crate) fn splice_tree(&mut self, tasks: Tasks) -> Res<SpliceTree> {
        let head = commit_of("HEAD").ok_or(Fail::Hard)?;
        let suffix = format!("/{STATE_FILE}");
        let paths: Vec<String> = self
            .state_files("HEAD")
            .iter()
            .filter_map(|file| file.strip_suffix(&suffix).map(str::to_string))
            .collect();
        let branch = self.monorepo_branch.clone();
        let mut nodes = Vec::new();
        for path in splices_in_order(false, &paths) {
            let (boundary, rebuild) = quietly(|| {
                (
                    self.splice_start(&path, "HEAD").ok().flatten(),
                    self.rebuild_splice(&path, "HEAD").ok().flatten(),
                )
            });
            let target = quietly(|| {
                self.require_splice_upstream(&path).ok()?;
                let target = self.resolve_upstream_target(&path, &branch).ok()?;
                commit_of(&target.reference)
            });
            let task = tasks
                .per_splice
                .iter()
                .find(|(done, _)| *done == path)
                .map(|(_, task)| task.clone());
            nodes.push(Node {
                synced: splice_config(&path, "commit", "HEAD"),
                path,
                boundary,
                rebuild,
                target,
                task,
            });
        }
        Ok(SpliceTree {
            head,
            nodes,
            next: tasks.next,
        })
    }
}

impl SpliceTree {
    /// The tree as a table, one row per splice, indented inside its parent,
    /// with each commit as <label> names it:
    ///
    /// ```text
    /// monorepo    H=pa
    /// vendor/a/   B=s  U=a2  R=pa'  T=a2  done
    ///   b/        B=s  U=b1  R=b1   T=b2  pending: merge
    ///     c/      B=s  U=c1  R=c1   T=c2  pending: merge, after b/
    /// next: fold
    /// ```
    pub fn render(&self, label: impl Fn(&str) -> String) -> String {
        let label = |id: &Option<String>| id.as_deref().map_or("-".to_string(), &label);
        let parent = |path: &str| {
            self.nodes
                .iter()
                .map(|node| node.path.as_str())
                .filter(|above| path.starts_with(&format!("{above}/")))
                .max_by_key(|above| above.len())
        };
        let depth = |path: &str| {
            let mut depth = 0;
            let mut at = path;
            while let Some(above) = parent(at) {
                depth += 1;
                at = above;
            }
            depth
        };
        let pending = |path: &str| {
            self.nodes
                .iter()
                .any(|node| node.path == path && matches!(node.task, Some(Task::Pending(_))))
        };
        let mut rows = vec![vec![
            "monorepo".to_string(),
            format!("H={}", label(&Some(self.head.clone()))),
        ]];
        for node in &self.nodes {
            let name = match parent(&node.path) {
                Some(above) => &node.path[above.len() + 1..],
                None => node.path.as_str(),
            };
            let mut task = match &node.task {
                None => String::new(),
                Some(Task::Done) => "done".to_string(),
                Some(Task::Failed) => "failed".to_string(),
                Some(Task::Conflict) => "conflict".to_string(),
                Some(Task::Pending(step)) => format!("pending: {step}"),
            };
            // Merges go top-down; fetches run side by side.
            if let Some(above) = parent(&node.path).filter(|above| pending(above)) {
                if node.task == Some(Task::Pending("merge")) {
                    let name = match parent(above) {
                        Some(top) => &above[top.len() + 1..],
                        None => above,
                    };
                    task.push_str(&format!(", after {name}/"));
                }
            }
            rows.push(vec![
                format!("{}{name}/", "  ".repeat(depth(&node.path))),
                format!("B={}", label(&node.boundary)),
                format!(
                    "U={}",
                    label(&Some(node.synced.clone()).filter(|s| !s.is_empty()))
                ),
                format!("R={}", label(&node.rebuild)),
                format!("T={}", label(&node.target)),
                task,
            ]);
        }
        let columns = rows.iter().map(Vec::len).max().unwrap_or(0);
        let widths: Vec<usize> = (0..columns)
            .map(|column| {
                rows.iter()
                    .filter_map(|row| row.get(column))
                    .map(|cell| cell.chars().count())
                    .max()
                    .unwrap_or(0)
            })
            .collect();
        let mut out = String::new();
        for row in &rows {
            let line = row
                .iter()
                .enumerate()
                .map(|(column, cell)| format!("{cell:<width$}", width = widths[column]))
                .collect::<Vec<_>>()
                .join("  ");
            out.push_str(line.trim_end());
            out.push('\n');
        }
        if let Some(next) = self.next {
            out.push_str(&format!("next: {next}\n"));
        }
        out
    }
}

/// Labels a commit for [`SpliceTree::render`]: by the name <named> gives it;
/// as a rebuild, name' for a commit with the subject of one <named> names,
/// the last one if several have it;
/// by its subject's label, the "a1" of "a1: a seed", as the scenarios name
/// their commits; "?" for a commit that isn't here yet; else by its short id.
pub fn labels<'a>(named: &'a [(&'a str, String)]) -> impl Fn(&str) -> String + 'a {
    let subject = |id: &str| {
        git(&["log", "-1", "--format=%s", id])
            .q()
            .out()
            .unwrap_or_default()
    };
    let named_subjects: Vec<(&str, String)> = named
        .iter()
        .map(|(name, id)| (*name, subject(id)))
        .collect();
    move |id: &str| {
        if let Some((name, _)) = named.iter().find(|(_, known)| known == id) {
            return (*name).to_string();
        }
        if !commit_here(id) {
            return "?".to_string();
        }
        let own = subject(id);
        if let Some((name, _)) = named_subjects.iter().rev().find(|(_, s)| *s == own) {
            return format!("{name}'");
        }
        if let Some((label, _)) = own.split_once(": ") {
            if label.chars().all(|c| c.is_ascii_alphanumeric())
                && label.chars().any(|c| c.is_ascii_digit())
            {
                return label.to_string();
            }
        }
        short(id).to_string()
    }
}
