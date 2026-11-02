//! What the check-drawing script reads from a repository, from git-splice's own
//! code, so a drawing is checked against what the tool really does. The first
//! part of moving check-drawing to Rust: the script still reads the drawings.

use git_splice::rebuild::{splice_lineage, splice_lineage_to_mount};
use git_splice::repo::{current_branch, Repo};
use git_splice::util::{Fail, Res};
use std::io::Write;
use std::process::ExitCode;

/// Writes fields that may hold anything but NUL, each ending with a NUL.
fn print_fields(fields: &[String]) {
    let mut out = std::io::stdout();
    for field in fields {
        let _ = out.write_all(field.as_bytes());
        let _ = out.write_all(&[0]);
    }
}

/// The folders the splice had on HEAD's first-parent history, as the rebuild
/// follows it back through moves: the mount (nothing if there's none), then
/// each path and the range (rev-list syntax) of commits it applies to, newest
/// first. The last range starts at the mount: before, the folder was no splice,
/// or another one.
fn lineage(path: &str) {
    let to_sync = splice_lineage(path, "HEAD");
    let to_mount = splice_lineage_to_mount(&to_sync.path, &to_sync.upper);
    let mut fields = vec![to_mount.mount.clone()];
    for segment in to_sync.moves.iter().chain(&to_mount.moves) {
        fields.push(segment.path.clone());
        fields.push(segment.range.clone());
    }
    fields.push(to_mount.path.clone());
    fields.push(
        if to_mount.mount.is_empty() || !git_splice::rebuild::has_parent(&to_mount.mount) {
            to_mount.upper.clone()
        } else {
            format!("{}^1..{}", to_mount.mount, to_mount.upper)
        },
    );
    print_fields(&fields);
}

/// Every state file in commit <commit>, at any depth.
fn state_files(commit: &str) {
    print_fields(&Repo::default().state_files(commit));
}

/// The fetched ref of what the splice syncs with on the current branch.
fn target_ref(path: &str) -> Res<()> {
    let mut repo = Repo::default();
    repo.require_splice_upstream(path)?;
    let branch = current_branch()?;
    let upstream_branch = repo.upstream_branch_for(path, &branch, None)?;
    println!("{}", repo.splice_ref(path, &upstream_branch));
    Ok(())
}

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let argv: Vec<&str> = argv.iter().map(String::as_str).collect();
    let result = match argv.as_slice() {
        ["lineage", path] => {
            lineage(path);
            Ok(())
        }
        ["state-files", commit] => {
            state_files(commit);
            Ok(())
        }
        ["target-ref", path] => target_ref(path),
        _ => {
            eprintln!(
                "usage: check-drawing (lineage <path> | state-files <commit> | target-ref <path>)"
            );
            Err(Fail::Hard)
        }
    };
    if result.is_ok() {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}
