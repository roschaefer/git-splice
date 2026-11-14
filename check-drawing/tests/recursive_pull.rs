//! One `git splice pull --recursive`, paused at each step: the splice tree
//! as text, with what the pull still does for each splice, and the step-by-step
//! page's drawing of that step checked against the same state.

use check_drawing::check::{Checker, Labels};
use check_drawing::tree::{ascii, Marks};
use git_splice::context::ExecutionContext;
use git_splice::execution::{ExecutionEvent, ExecutionOutcome};
use git_splice::pull::{self, PullExecution};
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
    let marks = Marks {
        pulled: true,
        carried: false,
    };
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
    let mut execution =
        pull::start(&mut context, &["--recursive".into(), "vendor/a".into()]).unwrap();
    let mut steps = vec![format!("start:\n{}", tree(&execution, &named))];
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
        let step = match event {
            ExecutionEvent::AfterFetch { fetched } => {
                let paths: Vec<String> = fetched.into_iter().map(|f| f.path).collect();
                // e/ came with a's merge; the page's drawing of that merge
                // shows it fetched, as it is only from here on.
                if paths == ["vendor/a/e"] {
                    drawing("step-a.drawio.svg", &[("pa", "HEAD")]);
                }
                format!("after-fetch {}", paths.join(" "))
            }
            ExecutionEvent::AfterMerge {
                path, head_after, ..
            } => {
                let (name, page) = match path.as_str() {
                    "vendor/a" => ("pa", None),
                    "vendor/a/b" => ("pb", Some(("step-b.drawio.svg", vec![("pb", "HEAD")]))),
                    "vendor/a/b/c" => ("pc", Some(("step-c.drawio.svg", vec![("pc", "HEAD")]))),
                    "vendor/a/d" => (
                        "pd",
                        Some(("step-d.drawio.svg", vec![("pd", "HEAD"), ("pc", "HEAD~1")])),
                    ),
                    other => panic!("unexpected merge of {other}"),
                };
                named.push((name, head_after));
                if let Some((file, revs)) = page {
                    drawing(file, &revs);
                }
                format!("after-merge {path}")
            }
            ExecutionEvent::BeforeFold { .. } => "before-fold".to_string(),
            ExecutionEvent::AfterFold { head_after, .. } => {
                named.push(("p", head_after));
                drawing("step-folded.drawio.svg", &[("p", "HEAD")]);
                "after-fold".to_string()
            }
            _ => unreachable!(),
        };
        steps.push(format!("{step}:\n{}", tree(&execution, &named)));
    }
    let observed = steps.join("\n");
    println!("{observed}");
    assert_eq!(
        observed,
        r#"start:
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
   └─ e/      (e1)

after-fetch vendor/a/e:
monorepo      (pa*)
└─ vendor/a/  (a2*)  done
   ├─ b/      (b1)   pending: merge
   │  └─ c/   (c1)   pending: merge, after vendor/a/b/
   ├─ d/      (d1)   pending: merge
   └─ e/      (e1)   pending: merge

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
   └─ e/      (e1)           done
next: clean up
"#,
        "observed trees:\n{observed}"
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
        r#"monorepo      (pa*)
└─ vendor/a/  (a2*) … [pa']       done
   ├─ b/      (b1) … [m1'] (b2!)  conflict
   │  └─ c/   (c1)                blocked by vendor/a/b/
   ├─ d/      (d1)                blocked by vendor/a/b/
   └─ e/      (e1)                done
"#,
        "observed tree:\n{observed}"
    );
}
