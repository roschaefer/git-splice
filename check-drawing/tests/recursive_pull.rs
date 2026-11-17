//! One `git splice pull --recursive`, paused at each step: the splice tree
//! as text, with what the pull still does for each splice, and the step-by-step
//! page's drawing of that step checked against the same state.

use check_drawing::check::{Checker, Labels};
use check_drawing::tree::{ascii, Mark, Marks};
use git_splice::context::ExecutionContext;
use git_splice::execution::{ExecutionEvent, ExecutionOutcome};
use git_splice::pull::{self, PullExecution};
use indoc::indoc;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

const PAGE: &str = "docs/09-scenarios/05-nested-splices/05-recursion/01-recursive-pull";

fn docs() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join(PAGE)
}

fn git(args: &[&str]) -> String {
    let output = std::process::Command::new("git")
        .args(args)
        .output()
        .unwrap();
    assert!(output.status.success(), "git {args:?}");
    String::from_utf8(output.stdout)
        .unwrap()
        .trim_end()
        .to_string()
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

/// The tree as text, each commit named by <named> or its subject, and what
/// <execution> still does for each splice.
fn tree(execution: &PullExecution, named: &[(&str, String)]) -> String {
    let revs: Vec<(&str, &str)> = named.iter().map(|(l, r)| (*l, r.as_str())).collect();
    let tasks = execution.tasks();
    let marks = Marks::from([(Mark::Pulled, "*"), (Mark::Conflict, "!")]);
    let mut text = ascii(&labels(&revs), &marks, &tasks.notes()).unwrap();
    if let Some(next) = tasks.next {
        text.push_str(&format!("next: {next}\n"));
    }
    text
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

#[derive(Debug, PartialEq, Eq)]
enum Checkpoint<'a> {
    Fetch(Vec<&'a str>),
    Merge(&'a str),
    BeforeFold,
    AfterFold,
}

struct Checkpoints<'context> {
    execution: PullExecution<'context>,
}

impl Checkpoints<'_> {
    fn expect(&mut self, expected: Checkpoint<'_>, check: impl FnOnce(&PullExecution)) {
        let outcome = self.execution.run_until(|_| true).unwrap();
        let ExecutionOutcome::Paused(event) = outcome else {
            panic!("expected {expected:?}, got {outcome:?}");
        };
        let observed = match &event {
            ExecutionEvent::AfterFetch { fetched } => {
                assert!(
                    fetched.iter().all(|f| !f.failed),
                    "fetch failed: {fetched:?}"
                );
                Checkpoint::Fetch(fetched.iter().map(|f| f.path.as_str()).collect())
            }
            ExecutionEvent::AfterMerge { path, .. } => Checkpoint::Merge(path),
            ExecutionEvent::BeforeFold { .. } => Checkpoint::BeforeFold,
            ExecutionEvent::AfterFold { .. } => Checkpoint::AfterFold,
            other => panic!("expected {expected:?}, got {other:?}"),
        };
        assert_eq!(observed, expected);
        check(&self.execution);
    }
}

fn with_checkpoints(execution: PullExecution, check: impl FnOnce(&mut Checkpoints)) {
    let mut checkpoints = Checkpoints { execution };
    check(&mut checkpoints);
    assert_eq!(
        checkpoints.execution.run_until(|_| true).unwrap(),
        ExecutionOutcome::Complete(0),
        "unconsumed checkpoint or unsuccessful pull"
    );
}

fn step_by_step(root: &Path) {
    step_by_step_scenario(root);
    // e1 isn't here until the pull fetches e's upstream: named by its hash.
    let e1 = git(&[
        "-C",
        root.join("upstream-e.git").to_str().unwrap(),
        "rev-parse",
        "main",
    ]);
    let mut named = vec![("s", git(&["rev-parse", "HEAD"])), ("e1", e1)];
    drawing("step-0.drawio.svg", &[("s", "HEAD")]);
    let mut context = ExecutionContext::new();
    let execution = pull::start(&mut context, &["--recursive".into(), "vendor/a".into()]).unwrap();
    let mut steps = vec![format!("start:\n{}", tree(&execution, &named))];
    with_checkpoints(execution, |checkpoints| {
        checkpoints.expect(
            Checkpoint::Fetch(vec!["vendor/a", "vendor/a/b", "vendor/a/b/c", "vendor/a/d"]),
            |execution| {
                steps.push(format!(
                    "after-fetch vendor/a vendor/a/b vendor/a/b/c vendor/a/d:\n{}",
                    tree(execution, &named)
                ));
            },
        );
        checkpoints.expect(Checkpoint::Merge("vendor/a"), |execution| {
            named.push(("pa", git(&["rev-parse", "HEAD"])));
            steps.push(format!(
                "after-merge vendor/a:\n{}",
                tree(execution, &named)
            ));
        });
        checkpoints.expect(Checkpoint::Fetch(vec!["vendor/a/e"]), |execution| {
            drawing("step-a.drawio.svg", &[("pa", "HEAD")]);
            steps.push(format!(
                "after-fetch vendor/a/e:\n{}",
                tree(execution, &named)
            ));
        });
        checkpoints.expect(Checkpoint::Merge("vendor/a/b"), |execution| {
            named.push(("pb", git(&["rev-parse", "HEAD"])));
            drawing("step-b.drawio.svg", &[("pb", "HEAD")]);
            steps.push(format!(
                "after-merge vendor/a/b:\n{}",
                tree(execution, &named)
            ));
        });
        checkpoints.expect(Checkpoint::Merge("vendor/a/b/c"), |execution| {
            named.push(("pc", git(&["rev-parse", "HEAD"])));
            drawing("step-c.drawio.svg", &[("pc", "HEAD")]);
            steps.push(format!(
                "after-merge vendor/a/b/c:\n{}",
                tree(execution, &named)
            ));
        });
        checkpoints.expect(Checkpoint::Merge("vendor/a/d"), |execution| {
            named.push(("pd", git(&["rev-parse", "HEAD"])));
            drawing("step-d.drawio.svg", &[("pd", "HEAD"), ("pc", "HEAD~1")]);
            steps.push(format!(
                "after-merge vendor/a/d:\n{}",
                tree(execution, &named)
            ));
        });
        checkpoints.expect(Checkpoint::BeforeFold, |execution| {
            steps.push(format!("before-fold:\n{}", tree(execution, &named)));
        });
        checkpoints.expect(Checkpoint::AfterFold, |execution| {
            named.push(("p", git(&["rev-parse", "HEAD"])));
            drawing("step-folded.drawio.svg", &[("p", "HEAD")]);
            steps.push(format!("after-fold:\n{}", tree(execution, &named)));
        });
    });
    let observed = steps.join("\n");
    println!("{observed}");
    assert_eq!(
        observed,
        indoc! {r#"
            start:
            monorepo      (s)
            └─ vendor/a/  (a1)  pending: fetch
               ├─ b/      (b1)  pending: fetch
               │  └─ c/   (c1)  pending: fetch
               └─ d/      (d1)  pending: fetch

            after-fetch vendor/a vendor/a/b vendor/a/b/c vendor/a/d:
            monorepo      (s)
            └─ vendor/a/  (a1)  pending: merge
               ├─ b/      (b1)  pending: merge, after vendor/a/
               │  └─ c/   (c1)  pending: merge, after vendor/a/b/
               └─ d/      (d1)  pending: merge, after vendor/a/

            after-merge vendor/a:
            monorepo      (pa*)
            └─ vendor/a/  (a2*)  done
               ├─ b/      (b1)   pending: merge
               │  └─ c/   (c1)   pending: merge, after vendor/a/b/
               ├─ d/      (d1)   pending: merge
               └─ e/      (e1*)

            after-fetch vendor/a/e:
            monorepo      (pa*)
            └─ vendor/a/  (a2*)  done
               ├─ b/      (b1)   pending: merge
               │  └─ c/   (c1)   pending: merge, after vendor/a/b/
               ├─ d/      (d1)   pending: merge
               └─ e/      (e1*)  pending: merge

            after-merge vendor/a/b:
            monorepo      (pb*)
            └─ vendor/a/  (a2) … [pb'*]  done
               ├─ b/      (b2*)          done
               │  └─ c/   (c1)           pending: merge
               ├─ d/      (d1)           pending: merge
               └─ e/      (e1)           done

            after-merge vendor/a/b/c:
            monorepo      (pc*)
            └─ vendor/a/  (a2) … [pc'*]  done
               ├─ b/      (b2) … [pc'*]  done
               │  └─ c/   (c2*)          done
               ├─ d/      (d1)           pending: merge
               └─ e/      (e1)           done

            after-merge vendor/a/d:
            monorepo      (pd*)
            └─ vendor/a/  (a2) … [pd'*]  done
               ├─ b/      (b2) … [pc'*]  done
               │  └─ c/   (c2*)          done
               ├─ d/      (d2*)          done
               └─ e/      (e1)           done

            before-fold:
            monorepo      (pd*)
            └─ vendor/a/  (a2) … [pd'*]  done
               ├─ b/      (b2) … [pc'*]  done
               │  └─ c/   (c2*)          done
               ├─ d/      (d2*)          done
               └─ e/      (e1)           done
            next: fold

            after-fold:
            monorepo      (p*)
            └─ vendor/a/  (a2*) … [p'*]  done
               ├─ b/      (b2*) … [p'*]  done
               │  └─ c/   (c2*)          done
               ├─ d/      (d2*)          done
               └─ e/      (e1*)          done
            next: clean up
        "#},
        "observed trees:\n{observed}"
    );
}

#[test]
fn ascii_splice_tree_before_and_after_recursive_pull() {
    isolated(
        "ascii_splice_tree_before_and_after_recursive_pull",
        |root| {
            step_by_step_scenario(root);
            let marks = Marks::from([(Mark::Pulled, "*")]);
            let notes = HashMap::from([("vendor/a/b".to_string(), "nested splice".to_string())]);
            assert_eq!(
                ascii(&labels(&[("s", "HEAD")]), &marks, &notes).unwrap(),
                indoc! {"
                    monorepo      (s)
                    └─ vendor/a/  (a1)
                       ├─ b/      (b1)  nested splice
                       │  └─ c/   (c1)
                       └─ d/      (d1)
                "}
            );
            let mut context = ExecutionContext::new();
            let mut execution =
                pull::start(&mut context, &["--recursive".into(), "vendor/a".into()]).unwrap();
            assert_eq!(execution.run().unwrap(), 0);
            assert_eq!(
                ascii(&labels(&[("p", "HEAD")]), &marks, &HashMap::new()).unwrap(),
                indoc! {"
                    monorepo      (p*)
                    └─ vendor/a/  (a2*) … [p'*]
                       ├─ b/      (b2*) … [p'*]
                       │  └─ c/   (c2*)
                       ├─ d/      (d2*)
                       └─ e/      (e1*)
                "}
            );
        },
    );
}

#[test]
fn ascii_uses_configured_markers_and_omits_unlisted_marks() {
    isolated(
        "ascii_uses_configured_markers_and_omits_unlisted_marks",
        |root| {
            step_by_step_scenario(root);
            let mut context = ExecutionContext::new();
            let mut execution =
                pull::start(&mut context, &["--recursive".into(), "vendor/a".into()]).unwrap();
            assert_eq!(execution.run().unwrap(), 0);
            let marks = Marks::from([(Mark::Pulled, "*")]);
            let custom = Marks::from([(Mark::Pulled, "++")]);
            let standard = ascii(&labels(&[("p", "HEAD")]), &marks, &HashMap::new()).unwrap();
            assert_eq!(
                ascii(&labels(&[("p", "HEAD")]), &custom, &HashMap::new()).unwrap(),
                standard.replace('*', "++")
            );
            assert_eq!(
                ascii(
                    &labels(&[("p", "HEAD")]),
                    &Marks::default(),
                    &HashMap::new()
                )
                .unwrap(),
                standard.replace('*', "")
            );
        },
    );
}

#[test]
fn recursive_pull_conflict_blocks_the_splices_after_it() {
    isolated(
        "recursive_pull_conflict_blocks_the_splices_after_it",
        conflict,
    );
}

/// The monorepo changed b's file where b's upstream did too: b's merge stops
/// in a conflict, and the splices after it wait on it.
fn conflict(root: &Path) {
    step_by_step_scenario(root);
    std::fs::write(
        "vendor/a/b/file.txt",
        std::fs::read_to_string("vendor/a/b/file.txt").unwrap() + "b in the monorepo\n",
    )
    .unwrap();
    git(&["commit", "-q", "-am", "m1: b in the monorepo"]);
    let e1 = git(&[
        "-C",
        root.join("upstream-e.git").to_str().unwrap(),
        "rev-parse",
        "main",
    ]);
    let mut named = vec![("e1", e1)];
    let mut context = ExecutionContext::new();
    let mut execution =
        pull::start(&mut context, &["--recursive".into(), "vendor/a".into()]).unwrap();
    let paused = execution
        .run_until(|event| matches!(event, ExecutionEvent::AfterMerge { .. }))
        .unwrap();
    let ExecutionOutcome::Paused(ExecutionEvent::AfterMerge { head_after, .. }) = paused else {
        panic!("no merge: {paused:?}");
    };
    named.push(("pa", head_after));
    assert_eq!(execution.run().unwrap(), 1);
    let observed = tree(&execution, &named);
    println!("{observed}");
    assert_eq!(
        observed,
        indoc! {r#"
            monorepo      (pa*)
            └─ vendor/a/  (a2*) … [pa']       done
               ├─ b/      (b1) … [m1'] (b2!)  conflict
               │  └─ c/   (c1)                blocked by vendor/a/b/
               ├─ d/      (d1)                blocked by vendor/a/b/
               └─ e/      (e1*)               done
        "#},
        "observed tree:\n{observed}"
    );
}
