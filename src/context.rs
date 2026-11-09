//! State shared by the operations in one execution.

use std::collections::HashMap;

#[derive(Default)]
pub struct ExecutionContext {
    pub(crate) configuration: crate::config::Configuration,
    pub(crate) checkpointing: bool,
    pub(crate) content_trees: HashMap<String, String>,
    pub(crate) supplied_rebuilds: HashMap<String, String>,
}

impl ExecutionContext {
    pub fn new() -> Self {
        Self::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::repo::{Repo, Uncommitted};
    use crate::util::Temp;
    use std::path::PathBuf;
    use std::process::Command;

    struct RestoreDirectory(PathBuf);

    impl Drop for RestoreDirectory {
        fn drop(&mut self) {
            std::env::set_current_dir(&self.0).unwrap();
        }
    }

    fn git(args: &[&str]) {
        let output = Command::new("git")
            .args(["-c", "user.name=Test", "-c", "user.email=test@example.com"])
            .args(args)
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    fn rebuilt(context: &mut ExecutionContext) -> String {
        let mut repo = Repo::new(context, Default::default());
        repo.open().unwrap();
        repo.rebuild_splice("vendor/a", "HEAD").unwrap().unwrap()
    }

    #[test]
    fn shared_context_reuses_immutable_trees_but_reads_current_history_and_worktree() {
        let directory = Temp::new();
        std::fs::create_dir_all(directory.path.join("vendor/a")).unwrap();
        let _restore = RestoreDirectory(std::env::current_dir().unwrap());
        std::env::set_current_dir(&directory.path).unwrap();
        git(&["init", "-q", "--initial-branch=main"]);
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
    }
}
