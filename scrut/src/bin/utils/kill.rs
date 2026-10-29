/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

use anyhow::Result;
use scrut::output::DetachedProcess;

#[cfg(unix)]
pub(crate) fn kill_detached_process(
    messages: &mut Vec<String>,
    detached_process: &DetachedProcess,
) -> Result<()> {
    if detached_process.signal.is_off() {
        messages.push(format!(
            "ℹ️ Cleanup of detached process disabled, ignoring PID {}",
            detached_process.pid
        ));
        return Ok(());
    }
    let signal = detached_process.signal.clone().to_nix()?;
    messages.push(format!(
        "🗑️ Sending {signal} to detached process with PID {}",
        detached_process.pid
    ));
    let result = nix::sys::signal::kill(
        nix::unistd::Pid::from_raw(detached_process.pid as i32),
        signal,
    );
    if let Err(err) = result {
        messages.push(format!(
            "❌ Failed to kill detached process with PID {}: {}",
            detached_process.pid, err
        ));
    }
    Ok(())
}

#[cfg(windows)]
pub(crate) fn kill_detached_process(
    messages: &mut Vec<String>,
    detached_process: &DetachedProcess,
) -> Result<()> {
    messages.push(format!(
        "⚠️ Windows support for reaping detached processes not implemented. Ignoring process with PID {}",
        detached_process.pid,
    ));
    Ok(())
}
