# --continue-from

Continue fetch, pull or push from the full JSON payload emitted by a stopped
handler. Completed work stays applied; the stopped handler is consumed.

```fish
git splice pull --recursive --exec 'cat; exit 1' vendor/a >../checkpoint.json
```

That invocation stops with a nonzero status. Save the next payload to a
different file so shell redirection cannot truncate the input:

```fish
git splice pull --continue-from ../checkpoint.json --exec 'cat; exit 1' >../next-checkpoint.json
```

Use the same operation as the payload. `-` reads the payload from stdin.
Options and paths come from the saved state, so only `--exec` may be supplied
again. CLI handlers require that flag again; configured handlers are restored
from their committed sources and need no script argument.

## What resumes

The next pending handler at the same checkpoint runs first, if any. Then the
algorithm proceeds to its next operation. Completed fetches, merges and pushes
are not replayed. A prepared push remains pinned to its commit.

If a build or download failed, repair and verify it before continuing: the
failed handler is not retried. A nonzero inspection pause follows exactly the
same rule. To run checks afresh, start a new invocation instead of continuing.

A successful continuation can finish without emitting another payload. If
handlers continue to stop, each new payload records the next position.

The [JSON inspection scenario](../../../09-scenarios/01-everyday-sync/05-exec-report/payload.md)
shows the full handoff. The
[recursive walkthrough](../../../09-scenarios/05-nested-splices/05-recursion/01-recursive-pull/discovered-top-down.md#a-recursive-pull)
checks an intermediate tree diagram against the paused repository, then
continues through the remaining fetch, merge and fold checkpoints.

## Repository validation

Continuation checks repository/worktree identity, branch, fetched refs,
effective Git configuration and the recursive pull boundary.

- Push requires exactly unchanged HEAD.
- Fetch and pull allow repair commits extending the saved HEAD, provided the
  committed `.splice` and `.spliceconfig` files do not change.
- A reset away from the saved history, changed fetched refs, changed branch or
  changed configuration requires a new operation.

A failed Git operation or merge conflict still uses the command's normal
resolution instructions. A saved payload does not recover a process killed
halfway through a Git operation or network upload.

## Returning a rebuilt commit

At a push's `after-rebuild`, the supported result field can replace the
prepared commit. Read the [result contract](01-json-payload.md#result) and
[worked example](../../../09-scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/edit-with-exec.md).
All other fields are returned unchanged.
