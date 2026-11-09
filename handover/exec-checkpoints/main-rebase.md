# Rebase onto main

Requested after the execution-context refactor. The previous tested PR head was
`dae5b8f9e7aa96ff12407301eba56ddaf3c740d9`, based on pile commit `070e2ef`.
The new base is main commit `3f737e61a7546e584018a2c1de5fbf6847927e4a`.
Backup branch: `backup/exec-checkpoints-before-main-3f737e6`.

Only the PR's own commits were replayed with an explicit `rebase --onto`;
the old pile history was excluded. The GitHub PR must now target main.

## Changes in main that affect this PR

| Main change | Effect and resolution |
|---|---|
| #461: pull --all recursively discovers children and folds each top-level group separately | MergeProgress now treats pull --all as recursive. Continuation saves fold_roots so resumed folding uses the same root groups and messages as ordinary pull. A paused two-root regression compares trees, commit counts and messages with ordinary pull. The fold guard is restricted to pull, so fetch --all can coexist with an unrelated SPLICE_PULL_START. |
| #455: fetch nested splices introduced by pull and clone | Preserve main's clone and repository-discovery changes. MergeProgress discovers children after every pull, even without --recursive, and exposes the ensuing fetch checkpoint before any requested child merge. A regression verifies a nonrecursive pull fetches a new child without pulling it. |
| Recursive cycle protection | Retain main's splice-id check in the resumable merge loop, including its --all behavior, so copied ancestors cannot expand recursion indefinitely. |
| #454: reject explicitly overlapping pull selections | Retain main's selection validation; existing nested tests cover it. |
| #461: recursive fold uses the root's pull message and per-root commit grouping | Keep main's fold implementation, including conflict-message cleanup and Unicode path parsing; expose it to the checkpoint runner. |
| Removed step-by-step.md and ref-replay helpers | Keep the deletion. Adapt the retained discovered-top-down.md walkthrough to actually pause at after-fetch, after-merge, before-fold and after-fold, checking removed-step.drawio.svg against the paused state. Update the command-reference link. |
| Design/docs/check-drawing reorganizations and scrut updates | Keep main's files and the moved Git-trace link. Update the context refactor's checker call sites against main. Run all documentation and drawing checks. |
| Release 0.21.0 and dependency maintenance | Keep main's package version and existing dependency versions; retain the PR's added serde dependencies. |

The old `cd83387` Unicode-folding fix was dropped because main's replacement
fold implementation already includes that handling. The old stale-fold guard
commit now only changes checkpoint behavior and removes a duplicate completion;
ordinary pull retains main's guard.

The substantive main adaptation after replay is `dc10caf`.
Fetch/push checkpoint commits and LFS prototype commits replayed unchanged.
The context refactor required adapting its Repo initialization to main's code.

## Verification

- Focused checkpoint/nested tests passed (110 before the final fetch guard case).
- All 22 checkpoint tests passed after adding the fetch --all guard regression.
- Lint and formatting passed.
- Documentation: 153 documents, 1,850 testcases, 178 label pages and 117 diagram
  placements passed, including the real paused-state diagram walkthrough.
- Current-system Nix flake checks passed on final source.
- Final full regression verification passed: 892 Bats tests and 48 Rust tests.
  The first run failed one existing submodule-clone test; both matching tests
  passed on isolated retry and the final full run passed without code changes
  to clone. The initial failure was transient.

Logs: `/tmp/git-splice-main-{focused-built,final-checkpoints,docs,final-tests,final-flake}.log`.
