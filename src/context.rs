//! State shared by the operations in one execution.

use crate::execution::ExecutionEvent;
use crate::repo::STATE_FILE;
use crate::util::*;
use std::collections::HashMap;

type Observer = Box<dyn FnMut(&ExecutionEvent) + Send + Sync>;

#[derive(Default)]
pub struct ExecutionContext {
    observer: Option<Observer>,
    captured_events: Option<Vec<ExecutionEvent>>,
    content_trees: HashMap<String, String>,
    pub(crate) supplied_rebuilds: HashMap<String, String>,
}

impl ExecutionContext {
    pub fn new() -> Self {
        Self::default()
    }

    /// Observes completed steps synchronously. No observer is installed by default.
    pub fn set_observer(&mut self, observer: impl FnMut(&ExecutionEvent) + Send + Sync + 'static) {
        self.observer = Some(Box::new(observer));
    }

    pub fn clear_observer(&mut self) {
        self.observer = None;
    }

    pub(crate) fn observing(&self) -> bool {
        self.observer.is_some() || self.captured_events.is_some()
    }

    pub(crate) fn emit(&mut self, event: ExecutionEvent) {
        if let Some(observer) = &mut self.observer {
            observer(&event);
        }
        if let Some(events) = &mut self.captured_events {
            events.push(event);
        }
    }

    pub(crate) fn capture_events(&mut self) {
        debug_assert!(self.captured_events.is_none());
        self.captured_events = Some(Vec::new());
    }

    pub(crate) fn take_events(&mut self) -> Vec<ExecutionEvent> {
        self.captured_events.take().unwrap_or_default()
    }

    /// Folder tree <tree> without its state file. The same folder tree recurs
    /// in every commit that doesn't touch it.
    pub(crate) fn strip_state_tree(&mut self, tree: &str) -> Res<String> {
        if let Some(stripped) = self.content_trees.get(tree) {
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
        self.content_trees.insert(tree.to_string(), result.clone());
        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::repo::{Repo, Uncommitted};
    use crate::util::test_repo::{git, with_repository};

    fn rebuilt(context: &mut ExecutionContext) -> String {
        let mut repo = Repo::new(context, Default::default());
        repo.open().unwrap();
        repo.rebuild_splice("vendor/a", "HEAD").unwrap().unwrap()
    }

    #[test]
    fn shared_context_reuses_immutable_trees_but_reads_current_history_and_worktree() {
        with_repository(|| {
            std::fs::create_dir_all("vendor/a").unwrap();
            std::fs::write(
                "vendor/a/.splice",
                "[splice]\n id = test\n[upstream \"origin\"]\n url = ../upstream.git\n",
            )
            .unwrap();
            std::fs::write("vendor/a/file", "one").unwrap();
            git(&["add", "."]);
            git(&["commit", "-qm", "mount"]);
            let mut context = ExecutionContext::new();
            let first = rebuilt(&mut context);
            let cached = context.content_trees.len();
            assert!(cached > 0);
            git(&["commit", "--allow-empty", "-qm", "empty"]);
            assert_eq!(rebuilt(&mut context), first);
            assert_eq!(context.content_trees.len(), cached);

            std::fs::write("vendor/a/file", "two").unwrap();
            git(&["add", "."]);
            git(&["commit", "-qm", "changed"]);
            let changed = rebuilt(&mut context);
            assert_ne!(changed, first);
            let cached = context.content_trees.len();
            git(&["commit", "--amend", "-qm", "reworded"]);
            assert_ne!(rebuilt(&mut context), changed);
            assert_eq!(context.content_trees.len(), cached);

            crate::status::run(&mut context, &[]).unwrap();
            let mut repo = Repo::new(&mut context, Default::default());
            assert!(matches!(
                repo.has_uncommitted_changes("vendor/a"),
                Uncommitted::NoChanges
            ));
            std::fs::write("vendor/a/file", "uncommitted").unwrap();
            let mut repo = Repo::new(&mut context, Default::default());
            assert!(matches!(
                repo.has_uncommitted_changes("vendor/a"),
                Uncommitted::Changes
            ));
        });
    }
}
