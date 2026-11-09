/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

use std::num::NonZeroUsize;
use std::thread::{self};

/// Default amount of parallel executions. This number often corresponds to the
/// amount of CPUs or computer has, but it may diverge in various cases.
pub fn default_parallel_count() -> usize {
    thread::available_parallelism()
        .unwrap_or(NonZeroUsize::new(1).expect("1 > 0"))
        .get()
}

/// Runs `start`, which starts a process, while no other thread starts one.
///
/// A process inherits the pipes and file descriptors that are open, and not
/// yet marked close-on-exec, at the moment it is created. On some platforms,
/// starting a process opens such a descriptor for a moment, and a process
/// another thread starts in that moment (see `--jobs`) inherits it and keeps
/// it open for as long as it runs:
///
/// - Where there is no `pipe2()`, both subprocess and the standard library
///   (which portable-pty uses for interactive test cases) create pipes with
///   `pipe()` and mark them close-on-exec only afterwards. An inherited
///   STDIN never reaches EOF, so the test case reading it waits until its
///   timeout. An inherited status pipe, which the standard library reads
///   until EOF to learn that `exec()` succeeded, blocks the start of an
///   interactive test case until the other process exits.
/// - On Windows, subprocess marks the child's ends of the pipes inheritable
///   before `CreateProcess()`, which hands every inheritable handle to the
///   new process.
///
/// Starting one process at a time there closes that gap.
pub(crate) fn start_one_at_a_time<T>(start: impl FnOnce() -> T) -> T {
    #[cfg(any(
        target_os = "aix",
        target_vendor = "apple",
        target_os = "haiku",
        windows
    ))]
    let _one_at_a_time = {
        static STARTING: std::sync::Mutex<()> = std::sync::Mutex::new(());
        STARTING
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    };
    start()
}
