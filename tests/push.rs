mod common;

use common::{git, push_ahead, with_repository};
use git_splice::context::ExecutionContext;
use git_splice::execution::ExecutionEvent;
use std::sync::{Arc, Mutex};

#[test]
fn observer_sees_rebuilt_objects_before_publication_and_remote_ref_afterward() {
    with_repository(|| {
        push_ahead();
        let events = Arc::new(Mutex::new(Vec::new()));
        let recorded = Arc::clone(&events);
        let mut context = ExecutionContext::new();
        context.set_observer(move |event| {
            match event {
                ExecutionEvent::AfterRebuild { path, commit } => {
                    assert_eq!(path, "vendor/a");
                    assert_eq!(git(&["cat-file", "-t", commit]), "commit");
                    assert!(git(&[
                        "--git-dir=../upstream.git",
                        "for-each-ref",
                        "refs/heads/topic"
                    ])
                    .is_empty());
                }
                ExecutionEvent::AfterPush { path, commit } => {
                    assert_eq!(path, "vendor/a");
                    assert_eq!(
                        git(&["--git-dir=../upstream.git", "rev-parse", "refs/heads/topic"]),
                        *commit
                    );
                }
                _ => panic!("unexpected push event: {event:?}"),
            }
            recorded.lock().unwrap().push(event.clone());
        });
        let args = [
            "--all".into(),
            "--force".into(),
            "--branch".into(),
            "topic".into(),
        ];
        assert_eq!(git_splice::push::run(&mut context, &args).unwrap(), 0);
        let commit = git(&["--git-dir=../upstream.git", "rev-parse", "refs/heads/topic"]);
        assert_eq!(
            *events.lock().unwrap(),
            vec![
                ExecutionEvent::AfterRebuild {
                    path: "vendor/a".into(),
                    commit: commit.clone()
                },
                ExecutionEvent::AfterPush {
                    path: "vendor/a".into(),
                    commit
                },
            ]
        );
        context.clear_observer();
        events.lock().unwrap().clear();
        std::fs::write("vendor/a/file.txt", "another change\n").unwrap();
        git(&["add", "."]);
        git(&["commit", "-qm", "change splice"]);
        let before = git(&["--git-dir=../upstream.git", "rev-parse", "refs/heads/topic"]);
        assert_eq!(git_splice::push::run(&mut context, &args).unwrap(), 0);
        assert_ne!(
            git(&["--git-dir=../upstream.git", "rev-parse", "refs/heads/topic"]),
            before
        );
        assert!(events.lock().unwrap().is_empty());
    });
}
