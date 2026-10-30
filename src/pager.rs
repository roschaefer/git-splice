//! Paging for diff and log, the way Git pages its own commands.

use crate::util::*;
use std::os::fd::AsRawFd;
use std::process::{Command, Stdio};

extern "C" {
    fn isatty(fd: i32) -> i32;
    fn dup(fd: i32) -> i32;
    fn dup2(from: i32, to: i32) -> i32;
    fn close(fd: i32) -> i32;
}

pub fn stdout_is_terminal() -> bool {
    // SAFETY: isatty only reads the file descriptor's number.
    unsafe { isatty(1) == 1 }
}

/// The pager for this command. pager.splice takes precedence over an ordinary
/// GIT_PAGER value, just as pager.log does for `git log`; the special
/// GIT_PAGER=cat exported by `git --no-pager` still disables paging globally.
fn splice_pager() -> String {
    let git_pager = || git(&["var", "GIT_PAGER"]).out().unwrap_or_default();
    let pager = if std::env::var("GIT_PAGER").as_deref() == Ok("cat") {
        "cat".to_string()
    } else if let Some(configured) = git(&["config", "--get", "pager.splice"]).q().out() {
        match git(&["config", "--type=bool", "--get", "pager.splice"])
            .q()
            .out()
        {
            Some(flag) if flag == "true" => git_pager(),
            Some(_) => "cat".to_string(),
            None => configured,
        }
    } else {
        git_pager()
    };
    if pager.is_empty() {
        "cat".to_string()
    } else {
        pager
    }
}

/// Runs <producer> with stdout through <pager>, and keeps what matters of the
/// statuses. A producer SIGPIPE is normal when a successful pager quits early;
/// a pager startup or runtime failure must still reach the caller: once it's
/// gone, the producer's failure to write is a consequence, not the cause.
fn pipe_to_pager(producer: impl FnOnce() -> i32, pager: &str) -> i32 {
    std::env::set_var("GIT_PAGER_IN_USE", "true");
    if std::env::var_os("LESS").is_none() {
        std::env::set_var("LESS", "FRX");
    }
    if std::env::var_os("LV").is_none() {
        std::env::set_var("LV", "-c");
    }
    // Pager values are shell commands by Git's documented configuration
    // contract, so run them in a shell, as Git does.
    let child = Command::new("sh")
        .arg("-c")
        .arg(pager)
        .stdin(Stdio::piped())
        .spawn();
    let Ok(mut child) = child else {
        return 127;
    };
    let Some(pipe) = child.stdin.take() else {
        return 1;
    };
    // SAFETY: only duplicates and closes file descriptors this process owns.
    let saved = unsafe {
        let saved = dup(1);
        dup2(pipe.as_raw_fd(), 1);
        saved
    };
    drop(pipe);
    let producer_status = producer();
    // SAFETY: as above. The pager sees the end of its input here.
    unsafe {
        dup2(saved, 1);
        close(saved);
    }
    let pager_status = child.wait().map_or(1, status_code);
    if pager_status != 0 {
        return pager_status;
    }
    if producer_status == 141 {
        0
    } else {
        producer_status
    }
}

/// Runs a producer through Git's pager when stdout is a terminal. Redirected
/// and piped output remains unpaged, as it does for Git's built-in commands.
pub fn page_git_output(producer: impl FnOnce() -> i32) -> i32 {
    if stdout_is_terminal() {
        pipe_to_pager(producer, &splice_pager())
    } else {
        producer()
    }
}
