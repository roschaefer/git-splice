use git_splice::context::ExecutionContext;
use git_splice::execution::{ExecutionEvent, ExecutionOutcome, FetchedUpstream};
use git_splice::{clone, pull, push};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;

static REPOSITORY: Mutex<()> = Mutex::new(());

struct Fixture {
    path: &'static str,
    initial: &'static str,
    updated: &'static str,
}

struct Sandbox {
    previous: PathBuf,
    root: PathBuf,
}

impl Sandbox {
    fn new() -> Self {
        let previous = std::env::current_dir().unwrap();
        let root = std::env::temp_dir().join(format!(
            "splice-pause-scenario-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&root).unwrap();
        std::env::set_current_dir(&root).unwrap();
        Self { previous, root }
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        std::env::set_current_dir(&self.previous).unwrap();
        std::fs::remove_dir_all(&self.root).unwrap();
    }
}

fn git(args: &[&str]) -> String {
    let output = Command::new("git")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .args(args)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).unwrap().trim().into()
}

fn init(path: &str) {
    git(&["init", "-q", "--initial-branch=main", path]);
    git(&["-C", path, "config", "user.name", "Scenario"]);
    git(&["-C", path, "config", "user.email", "scenario@example.com"]);
}

impl Fixture {
    fn setup(&self, context: &mut ExecutionContext) -> String {
        init("upstream");
        git(&[
            "-C",
            "upstream",
            "config",
            "receive.denyCurrentBranch",
            "updateInstead",
        ]);
        std::fs::write("upstream/file", self.initial).unwrap();
        git(&["-C", "upstream", "add", "file"]);
        git(&["-C", "upstream", "commit", "-qm", "Initial upstream"]);
        let upstream = std::env::current_dir().unwrap().join("upstream");
        init("monorepo");
        std::env::set_current_dir("monorepo").unwrap();
        git(&["commit", "--allow-empty", "-qm", "Initial monorepo"]);
        clone::run(
            context,
            &[upstream.to_string_lossy().into_owned(), self.path.into()],
        )
        .unwrap();
        git(&["-C", "../upstream", "rev-parse", "HEAD"])
    }

    fn assert_diagram(&self, title: &str, commits: &[(&str, &str)], expected: &str) {
        let label = |id: String| {
            commits
                .iter()
                .find(|(_, sha)| *sha == id)
                .map(|(name, _)| name.to_string())
                .unwrap_or(id)
        };
        let branch = git(&["symbolic-ref", "--short", "HEAD"]);
        let head = git(&["rev-parse", "HEAD"]);
        let upstream = git(&["-C", "../upstream", "rev-parse", "HEAD"]);
        let upstream_file = git(&["-C", "../upstream", "show", "HEAD:file"]);
        let local_file = std::fs::read_to_string(Path::new(self.path).join("file")).unwrap();
        let diagram = format!(
            "monorepo/{branch} -> {}\n  {} = {:?}\nupstream/main -> {}\n  file = {:?}",
            label(head),
            self.path,
            local_file,
            label(upstream),
            upstream_file
        );
        println!("\n{title}\n{diagram}\n");
        assert_eq!(diagram, expected, "{title}");
    }
}

#[test]
fn pull_pauses_after_download_then_continues_to_merge() {
    let _lock = REPOSITORY.lock().unwrap();
    let _sandbox = Sandbox::new();
    let fixture = Fixture {
        path: "vendor/a",
        initial: "version 1",
        updated: "version 2",
    };
    let mut context = ExecutionContext::new();
    let original = fixture.setup(&mut context);
    let start = git(&["rev-parse", "HEAD"]);
    std::fs::write("../upstream/file", fixture.updated).unwrap();
    git(&["-C", "../upstream", "commit", "-qam", "Update upstream"]);
    let updated = git(&["-C", "../upstream", "rev-parse", "HEAD"]);
    let names = [
        ("S", start.as_str()),
        ("U1", original.as_str()),
        ("U2", updated.as_str()),
    ];
    fixture.assert_diagram(
        "Before pull",
        &names,
        r#"monorepo/main -> S
  vendor/a = "version 1"
upstream/main -> U2
  file = "version 2""#,
    );

    let mut execution = pull::start(&mut context, &[fixture.path.into()]).unwrap();
    let outcome = execution
        .run_until(|event| matches!(event, ExecutionEvent::AfterFetch { .. }))
        .unwrap();
    let url = std::env::current_dir()
        .unwrap()
        .parent()
        .unwrap()
        .join("upstream")
        .to_string_lossy()
        .into_owned();
    assert_eq!(
        outcome,
        ExecutionOutcome::Paused(ExecutionEvent::AfterFetch {
            fetched: vec![FetchedUpstream {
                path: fixture.path.into(),
                upstream: "origin".into(),
                url,
                failed: false
            }]
        })
    );
    fixture.assert_diagram(
        "Paused: downloaded, not merged",
        &names,
        r#"monorepo/main -> S
  vendor/a = "version 1"
upstream/main -> U2
  file = "version 2""#,
    );

    let outcome = execution
        .run_until(|event| matches!(event, ExecutionEvent::AfterMerge { .. }))
        .unwrap();
    let merged = git(&["rev-parse", "HEAD"]);
    assert_eq!(
        outcome,
        ExecutionOutcome::Paused(ExecutionEvent::AfterMerge {
            path: fixture.path.into(),
            head_before: start.clone(),
            head_after: merged.clone()
        })
    );
    let names = [("P", merged.as_str()), ("U2", updated.as_str())];
    fixture.assert_diagram(
        "Continued: merged",
        &names,
        r#"monorepo/main -> P
  vendor/a = "version 2"
upstream/main -> U2
  file = "version 2""#,
    );
    assert_eq!(git(&["rev-parse", "HEAD^"]), start);
    assert_eq!(execution.run(), Ok(0));
    assert_eq!(
        execution.run_until(|_| true),
        Ok(ExecutionOutcome::Complete(0))
    );
    assert_eq!(git(&["rev-parse", "HEAD"]), merged);
}

#[test]
fn push_pauses_with_a_prepared_commit_then_continues_to_publish() {
    let _lock = REPOSITORY.lock().unwrap();
    let _sandbox = Sandbox::new();
    let fixture = Fixture {
        path: "vendor/a",
        initial: "version 1",
        updated: "version 2",
    };
    let mut context = ExecutionContext::new();
    let original = fixture.setup(&mut context);
    std::fs::write("vendor/a/file", fixture.updated).unwrap();
    git(&["add", "vendor/a/file"]);
    git(&["commit", "-qm", "Update monorepo"]);
    let local = git(&["rev-parse", "HEAD"]);
    let names = [("M", local.as_str()), ("U1", original.as_str())];
    fixture.assert_diagram(
        "Before push",
        &names,
        r#"monorepo/main -> M
  vendor/a = "version 2"
upstream/main -> U1
  file = "version 1""#,
    );

    let mut execution = push::start(&mut context, &[fixture.path.into()]).unwrap();
    let outcome = execution
        .run_until(|event| matches!(event, ExecutionEvent::AfterRebuild { .. }))
        .unwrap();
    let ExecutionOutcome::Paused(ExecutionEvent::AfterRebuild { path, commit }) = outcome else {
        panic!("expected prepared commit, got {outcome:#?}");
    };
    assert_eq!(path, fixture.path);
    assert_eq!(git(&["show", &format!("{commit}:file")]), fixture.updated);
    fixture.assert_diagram(
        "Paused: prepared, not published",
        &names,
        r#"monorepo/main -> M
  vendor/a = "version 2"
upstream/main -> U1
  file = "version 1""#,
    );

    let outcome = execution
        .run_until(|event| matches!(event, ExecutionEvent::AfterPush { .. }))
        .unwrap();
    assert_eq!(
        outcome,
        ExecutionOutcome::Paused(ExecutionEvent::AfterPush {
            path: fixture.path.into(),
            commit: commit.clone()
        })
    );
    let names = [("M", local.as_str()), ("R", commit.as_str())];
    fixture.assert_diagram(
        "Continued: published prepared commit",
        &names,
        r#"monorepo/main -> M
  vendor/a = "version 2"
upstream/main -> R
  file = "version 2""#,
    );
    assert_eq!(execution.run(), Ok(0));
    assert_eq!(
        execution.run_until(|_| true),
        Ok(ExecutionOutcome::Complete(0))
    );
    assert_eq!(git(&["-C", "../upstream", "rev-parse", "HEAD"]), commit);
}
