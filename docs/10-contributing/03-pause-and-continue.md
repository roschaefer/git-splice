# Pause and continue in memory

Rust callers can pause a pull or push and continue the retained execution in the
same process. The [public API scenarios](../../tests/pause_continue.rs) demonstrate
this with one splice and one file. They use no private execution machinery.

Run both scenarios and print the diagrams:

```sh
env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 cargo test --test pause_continue -- --nocapture
```

The fixture declares the splice path and the file's initial and updated contents:

```rust
let fixture = Fixture {
    path: "vendor/a",
    initial: "version 1",
    updated: "version 2",
};
```

Each diagram reads real Git refs and file contents and compares them with a
literal expected value. Letters name actual commit IDs; an unexpected commit
appears as its full SHA and fails the assertion.

## Pull: download, inspect, then merge

The upstream has version 2; the monorepo still has version 1. The test calls
`pull::start`, then `run_until` with a predicate selecting `AfterFetch`.
That call returns `Paused(AfterFetch { ... })` with the downloaded upstream entry.

```text
Paused: downloaded, not merged
monorepo/main -> S
  vendor/a = "version 1"
upstream/main -> U2
  file = "version 2"
```

Nothing runs in the background while the caller inspects the repository.
Calling `run_until` again, selecting `AfterMerge`, continues the same operation:

```text
Continued: merged
monorepo/main -> P
  vendor/a = "version 2"
upstream/main -> U2
  file = "version 2"
```

The test checks that P's parent is S. Calling `run()` finishes, and another
`run_until` returns `Complete(0)` without changing HEAD.

## Push: prepare, inspect, then publish

The monorepo has committed version 2; the upstream still has version 1.
The test calls `push::start`, then pauses at `AfterRebuild`:

```text
Paused: prepared, not published
monorepo/main -> M
  vendor/a = "version 2"
upstream/main -> U1
  file = "version 1"
```

The returned event contains a prepared commit R. The test reads R's file directly
from the local object database and checks that it contains version 2. R has not
been published. Continuing to `AfterPush` publishes that exact commit:

```text
Continued: published prepared commit
monorepo/main -> M
  vendor/a = "version 2"
upstream/main -> R
  file = "version 2"
```

Finishing and asking to continue again returns `Complete(0)` and retains R on the
upstream. M remains unchanged throughout the push.

## What can continue today?

Keep the `PullExecution` or `PushExecution` value and call `run_until` or `run`
again. These checkpoints support inspection; repository inputs must remain
unchanged while paused. Pull also checks tracked files, the index and pull
markers. The working directory and Git configuration must remain applicable
between `start` and the first call that drives execution.

This continuation is held in memory. Dropping it leaves completed changes applied
and abandons pending work. There is no CLI pause option or saved continuation
across processes yet.

For nested pulls around folding and rebase replay, see the
[development guide's recursive scenario](01-development.md).
