//! State shared by the operations in one execution.

use crate::execution::ExecutionEvent;
use crate::rebuild_cache::RebuildCache;
use crate::repo::STATE_FILE;
use crate::util::*;
use std::collections::HashMap;

type Observer = Box<dyn FnMut(&ExecutionEvent) + Send + Sync>;

/// State shared by the operations run in one repository. Use a new context
/// for another repository: it reads the rebuild cache of the first one.
#[derive(Default)]
pub struct ExecutionContext {
    observer: Option<Observer>,
    content_trees: HashMap<String, String>,
    pub(crate) supplied_rebuilds: HashMap<String, String>,
    rebuild_cache: Option<RebuildCache>,
    left_out: Vec<String>,
}

impl ExecutionContext {
    pub fn new() -> Self {
        Self::default()
    }

    /// The splices the last command failed for or left out, e.g. the ones a
    /// command over every splice leaves out because they are in the tree of
    /// a .splice that can't be read. Each says why as it happens; the
    /// command fails once it is done, naming them all.
    pub fn left_out(&self) -> &[String] {
        &self.left_out
    }

    /// <code>, or a failure if an operation left a splice out.
    pub fn exit_code(&self, code: i32) -> i32 {
        if self.left_out.is_empty() {
            code
        } else {
            code.max(1)
        }
    }

    /// Starts a command: what an earlier one left out is no longer its
    /// concern.
    pub(crate) fn start_command(&mut self) {
        self.left_out.clear();
    }

    pub(crate) fn leave_out(&mut self, path: &str) {
        if !self.left_out.iter().any(|left| left == path) {
            self.left_out.push(path.to_string());
        }
    }

    /// Observes completed steps synchronously. No observer is installed by default.
    ///
    /// Configure progress reporting before passing the context to an operation:
    ///
    /// ```
    /// use git_splice::context::ExecutionContext;
    /// use git_splice::execution::ExecutionEvent;
    ///
    /// let mut context = ExecutionContext::new();
    /// context.set_observer(|event| {
    ///     if let ExecutionEvent::AfterPush { path, commit } = event {
    ///         eprintln!("Published {path} at {commit}");
    ///     }
    /// });
    /// // Pass &mut context to a library operation, then disable reporting.
    /// context.clear_observer();
    /// ```
    pub fn set_observer(&mut self, observer: impl FnMut(&ExecutionEvent) + Send + Sync + 'static) {
        self.observer = Some(Box::new(observer));
    }

    pub fn clear_observer(&mut self) {
        self.observer = None;
    }

    pub(crate) fn emit(&mut self, event: ExecutionEvent) {
        if let Some(observer) = &mut self.observer {
            observer(&event);
        }
    }

    /// The rebuilt commits of earlier runs, read on first use.
    pub(crate) fn rebuild_cache(&mut self) -> &mut RebuildCache {
        self.rebuild_cache.get_or_insert_with(RebuildCache::load)
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
    fn a_command_on_a_reused_context_starts_with_nothing_left_out() {
        with_repository(|| {
            let mut context = ExecutionContext::new();
            context.leave_out("vendor/a");
            Repo::new(&mut context, Default::default());
            assert!(context.left_out().is_empty());
            assert_eq!(context.exit_code(0), 0);
        });
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
