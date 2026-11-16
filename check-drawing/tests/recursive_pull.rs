//! Check the step-by-step drawings against one real recursive pull, paused
//! at each illustrated state.

use check_drawing::check::{Checker, Labels};
use git_splice::context::ExecutionContext;
use git_splice::execution::{ExecutionEvent, ExecutionOutcome};
use git_splice::pull;
use std::path::{Path, PathBuf};

const PAGE: &str = "docs/09-scenarios/05-nested-splices/05-recursion/01-recursive-pull";

fn docs() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join(PAGE)
}

const CHILD: &str = "CHECK_DRAWING_TEST_CHILD";

/// A folder that is removed when it goes out of scope, also after a panic.
struct Sandbox(PathBuf);

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// Runs test <name> in a child process of this test binary, in a folder of
/// its own: its environment and current directory stay out of other tests,
/// and the developer's Git configuration and GIT_* variables out of it. The
/// upstreams' https://git.example.com URLs lead to bare repositories in that
/// folder, which is removed afterwards.
fn isolated(name: &str, test: impl FnOnce(&Path)) {
    if std::env::var(CHILD).as_deref() == Ok(name) {
        test(&std::env::current_dir().unwrap());
        return;
    }
    let folder = std::env::temp_dir().join(format!("check-drawing-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&folder);
    std::fs::create_dir_all(folder.join("home")).unwrap();
    let sandbox = Sandbox(folder.canonicalize().unwrap());
    let root = &sandbox.0;
    let mut child = std::process::Command::new(std::env::current_exe().unwrap());
    child
        .args([name, "--exact", "--nocapture", "--test-threads=1"])
        .current_dir(root);
    for (key, _) in std::env::vars_os() {
        if key.to_string_lossy().starts_with("GIT_") {
            child.env_remove(&key);
        }
    }
    let mut config = vec![
        ("user.name".to_string(), "Test".to_string()),
        ("user.email".to_string(), "test@example.com".to_string()),
    ];
    for x in ["a", "b", "c", "d", "e"] {
        config.push((
            format!("url.{}/upstream-{x}.git.insteadOf", root.display()),
            format!("https://git.example.com/{x}.git"),
        ));
    }
    child
        .env(CHILD, name)
        .env("HOME", root.join("home"))
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_COUNT", config.len().to_string());
    for (index, (key, value)) in config.iter().enumerate() {
        child
            .env(format!("GIT_CONFIG_KEY_{index}"), key)
            .env(format!("GIT_CONFIG_VALUE_{index}"), value);
    }
    let status = child.status().unwrap();
    assert!(status.success(), "isolated test {name} failed: {status}");
}

/// The step-by-step page's state: its setup.bash, then the same upstream
/// changes as the page. Leaves the current directory in the monorepo.
fn step_by_step_scenario(root: &Path) {
    let script = r#"
        set -euo pipefail
        source "$1"
        source "$2"
        scenario_recursive_pull "$PWD/monorepo" "$PWD/upstream"
        for x in b c d; do
          git clone -q "https://git.example.com/$x.git" "$x-work"
          echo "$x upstream" >>"$x-work/file.txt"
          git -C "$x-work" commit -q -am "${x}2: $x upstream"
          git -C "$x-work" push -q origin main
        done
        git clone -q https://git.example.com/a.git a-work
        add_splice a-work https://git.example.com/e.git e main "add e"
        echo "a upstream" >>a-work/file.txt
        git -C a-work commit -q --amend -am "a2: a upstream, and e spliced in"
        git -C a-work push -q origin main
    "#;
    let fixtures =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../docs/tests/helpers/fixtures.bash");
    let status = std::process::Command::new("bash")
        .current_dir(root)
        .args(["-c", script, "scenario"])
        .arg(fixtures)
        .arg(docs().join("setup.bash"))
        .status()
        .unwrap();
    assert!(status.success());
    std::env::set_current_dir(root.join("monorepo")).unwrap();
}

fn labels(revs: &[(&str, &str)]) -> Labels {
    let mut labels = Labels::default();
    for (label, rev) in revs {
        labels.revs.insert(label.to_string(), rev.to_string());
    }
    labels
}

/// Checks the page's drawing <name> as the page does, with labels <revs>.
fn drawing(name: &str, revs: &[(&str, &str)]) {
    let path = docs().join(name);
    assert!(
        Checker::run(path.to_str().unwrap(), &labels(revs)),
        "{name} isn't the repository's tree"
    );
}

#[test]
fn recursive_pull_step_by_step() {
    isolated("recursive_pull_step_by_step", step_by_step);
}

fn step_by_step(root: &Path) {
    step_by_step_scenario(root);
    drawing("step-0.drawio.svg", &[("s", "HEAD")]);
    let mut context = ExecutionContext::new();
    let mut execution =
        pull::start(&mut context, &["--recursive".into(), "vendor/a".into()]).unwrap();
    let mut checked = vec!["step-0.drawio.svg"];
    let wanted = |event: &ExecutionEvent| {
        matches!(
            event,
            ExecutionEvent::AfterFetch { .. }
                | ExecutionEvent::AfterMerge { .. }
                | ExecutionEvent::BeforeFold { .. }
                | ExecutionEvent::AfterFold { .. }
        )
    };
    while let ExecutionOutcome::Paused(event) = execution.run_until(wanted).unwrap() {
        match event {
            ExecutionEvent::AfterFetch { fetched } => {
                let paths: Vec<String> = fetched.into_iter().map(|f| f.path).collect();
                // e/ came with a's merge; the page's drawing of that merge
                // shows it fetched, as it is only from here on.
                if paths == ["vendor/a/e"] {
                    drawing("step-a.drawio.svg", &[("pa", "HEAD")]);
                    checked.push("step-a.drawio.svg");
                }
            }
            ExecutionEvent::AfterMerge { path, .. } => {
                let page = match path.as_str() {
                    "vendor/a" => None,
                    "vendor/a/b" => Some(("step-b.drawio.svg", vec![("pb", "HEAD")])),
                    "vendor/a/b/c" => Some(("step-c.drawio.svg", vec![("pc", "HEAD")])),
                    "vendor/a/d" => {
                        Some(("step-d.drawio.svg", vec![("pd", "HEAD"), ("pc", "HEAD~1")]))
                    }
                    other => panic!("unexpected merge of {other}"),
                };
                if let Some((file, revs)) = page {
                    drawing(file, &revs);
                    checked.push(file);
                }
            }
            ExecutionEvent::BeforeFold { .. } => {}
            ExecutionEvent::AfterFold { .. } => {
                drawing("step-folded.drawio.svg", &[("p", "HEAD")]);
                checked.push("step-folded.drawio.svg");
            }
            _ => unreachable!(),
        };
    }
    assert_eq!(execution.run().unwrap(), 0);
    assert_eq!(
        checked,
        [
            "step-0.drawio.svg",
            "step-a.drawio.svg",
            "step-b.drawio.svg",
            "step-c.drawio.svg",
            "step-d.drawio.svg",
            "step-folded.drawio.svg",
        ]
    );
}
