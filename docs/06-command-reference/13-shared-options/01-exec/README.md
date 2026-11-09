# --exec

Run a command at synchronization checkpoints, with a JSON payload on stdin:

```fish
git splice pull --recursive --exec './check-update' vendor/a
```

`fetch`, `pull` and `push` support the same handler protocol. Typical handlers
fetch LFS content before checkout, check a build after a merge, log execution,
or pause so a caller can inspect the intermediate repository.

## Handler contract

The command runs through `sh`, regardless of the interactive shell. Each call
receives one complete JSON object followed by a newline on stdin. The CLI
handler runs at the repository root. Normal command diagnostics go to stderr;
stdout belongs to the handler.

| Exit status | Effect |
|---|---|
| Zero | Proceed to the next handler or operation. Handler stdout is not interpreted as a response. |
| Nonzero | Stop with completed work still applied. The handler can emit its payload so the caller can save and continue it. |

A failed build and an intentional inspection pause use the same nonzero
result. Neither rolls back a fetch, merge or upload that has already completed.
To return an edited rebuild, use the explicit
[`result.rebuilt_commit` field](01-json-payload.md#result), emit the payload and
stop; writing a commit ID to stdout while returning zero does not replace it.

The [JSON payload reference](01-json-payload.md) documents the fields and event
variants. The [payload scenario](../../../09-scenarios/01-everyday-sync/05-exec-report/payload.md)
captures a real payload, inspects its JSON, then feeds the complete file back
to the tool.

## Checkpoints

| Operation | Checkpoint | State when the handler runs |
|---|---|---|
| fetch, pull | `after-fetch` | A fetch batch has finished. Refs may have changed; the fetch itself has not checked out source. Runs before tracking or the next merge. |
| pull | `after-merge` | A splice update changed HEAD. Its changes are present in the repository. |
| pull | `before-fold` | Recursive updates have finished and are about to be folded. |
| pull | `after-fold` | Folding has finished and the recursive pull boundary has been removed. |
| push | `after-rebuild` | A prepared commit has passed the push checks, before upload. |
| push | `after-push` | Upload and local fetched-ref recording have completed; tracking has been attempted. |

An unchanged fetch still has a fetch checkpoint. A no-op merge or push has no
merge or push checkpoint. A recursive pull may discover or reload nested
upstreams and emit additional fetch checkpoints before their merges.
`pull --all` also uses recursive folding, with a separate resulting commit for
each top-level splice.

Fetching alone does not change the checked-out source. To identify which
applied update breaks a build, check at `after-merge`. To download LFS objects
before checkout, act at `after-fetch`. A Git error before the next checkpoint
still follows the command's normal diagnostics and conflict handling.

## Shared and nested handlers

An `exec` entry in committed [`.spliceconfig`](../../12-configuration.md#configured-hooks)
uses this same interface. Configured handlers inherit outermost first and run
in the directory containing their configuration. `hook_scope` identifies that
directory; fetch entries are filtered to those inheriting the handler.

An explicit CLI `--exec` replaces the configured chain for that invocation.
Incoming configuration can supply a handler before checkout. See the
configuration reference for source precedence, empty entries and the fact
that committed upstream handlers execute automatically.

## Executable examples

| Use case | Scenario |
|---|---|
| Inspect JSON and return the saved payload | [Payload, pause and continuation](../../../09-scenarios/01-everyday-sync/05-exec-report/payload.md). |
| Record every checkpoint | [JSON-lines logging across fetch, pull and push](../../../09-scenarios/01-everyday-sync/05-exec-report/logging.md). |
| Select events for arbitrary user logic | [A report of applied updates](../../../09-scenarios/01-everyday-sync/05-exec-report/README.md). |
| Download before checkout, then publish LFS objects | [Committed LFS handler](../../../09-scenarios/04-upstreams/08-lfs-upstream/01-cloned-by-hand/01-retrained-upstream/with-exec.md), [two splice upstreams](../../../09-scenarios/04-upstreams/08-lfs-upstream/02-push-to-upstreams/README.md). |
| Return an edited commit before publishing | [Edit a rebuilt commit](../../../09-scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/edit-with-exec.md). |
| Pause a recursive algorithm, check a tree diagram, resume | [Discover a recursive pull top-down](../../../09-scenarios/05-nested-splices/05-recursion/01-recursive-pull/discovered-top-down.md#a-recursive-pull). |

[Continuation](02-continue-from.md) explains what gets consumed and what must
remain unchanged. Execution checkpoints do not support `--rebase` yet; clone,
init, standalone merge and rebuild do not expose this handler interface.
