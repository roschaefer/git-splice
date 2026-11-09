# JSON payload

Each `--exec` call receives one versioned JSON object on stdin. Use `jq` or
another JSON parser; field order has no meaning. The
[payload scenario](../../../09-scenarios/01-everyday-sync/05-exec-report/payload.md)
shows actual fetch and merge payloads and resumes from the captured file.

## Envelope

| Field | JSON type | Meaning |
|---|---|---|
| `version` | integer | Currently `1`. Continuation refuses unsupported versions. |
| `operation` | string | `fetch`, `pull` or `push`; continue using the same command. |
| `sequence` | integer | Starts at one for each invocation and increases for each handler call. Continuation carries it forward. Several handlers at one checkpoint get separate sequence numbers. |
| `hook_scope` | string | Directory defining the configured handler, relative to the monorepo root. Empty for root handlers and CLI `--exec`. |
| `event` | object | The event-specific fields below, identified by `checkpoint`. |
| `repository` | object | Repository identity and state used to validate continuation. |
| `continuation` | object | Opaque remaining execution state. Preserve it unchanged. |
| `result` | object | Explicit optional response, currently `rebuilt_commit`. |

A handler can inspect any field. Only `result.rebuilt_commit` is a supported
edit; pass the complete object back otherwise unchanged. A summary or projected
view of a payload is useful for display but is not a continuation payload.
Unknown fields are refused when reading a continuation.

## Fetch event

`event.checkpoint` is `after-fetch`, with a `fetched` array. Each entry has:

| Field | JSON type | Meaning |
|---|---|---|
| `path` | string | Splice path relative to the monorepo root. |
| `upstream` | string | Upstream name within that splice, such as `origin`. |
| `url` | string | That upstream's Git URL. |
| `reference` | string | Local fetched reference, or commit ID for a commit pin. |
| `old` | string or null | Commit recorded at the reference before the fetch, if any. |
| `new` | string or null | Commit at the reference after the fetch, if available. |
| `synced` | string | Upstream commit recorded in the splice's `.splice`; may be empty before an initial push. |
| `failed` | boolean | Whether fetching this entry failed. Check this before treating its `new` value as a successful download. |

`old` and `new` describe fetched refs, not HEAD or checked-out files. They can
be equal. A failed entry can still have an old commit available at its ref.
Fetches sharing a URL run together, and the batch finishes before its handler
runs. Configured handlers receive the entries in their inherited scope; a root
CLI handler receives the complete batch.

For LFS, the `url`, `new` and `synced` values identify where to download the
needed content. They do not configure custom LFS endpoints automatically.

## Merge event

`event.checkpoint` is `after-merge`:

| Field | JSON type | Meaning |
|---|---|---|
| `path`, `upstream`, `url` | strings | Updated splice and its upstream. |
| `old`, `new` | strings | Synced commits before and after this update; an unset sync point is an empty string. |
| `target` | string or null | Resolved upstream target commit, if available. |
| `rebuilt_commit` | string | Rebuilt splice history used for classification, or an empty string when none was available. |
| `head_before`, `head_after` | strings | Monorepo HEAD before and after the update. |

The event is emitted only when HEAD changes. `new` is the splice's sync point;
`head_after` is the monorepo commit containing the update.

## Push events

`after-rebuild` and `after-push` share these event fields:

| Field | JSON type | Meaning |
|---|---|---|
| `path`, `upstream`, `url` | strings | Splice and publication destination. |
| `branch` | string | Upstream branch being pushed. |
| `label` | string | Human-readable destination label. |
| `old` | string or null | Fetched target known when the push was prepared. This is not a live query of the remote. |
| `synced` | string | Recorded synced commit, possibly empty. |
| `rebuilt_commit` | string | Prepared commit for publication. |

Before upload, `after-rebuild` allows an edited commit to be returned through
`result`. At `after-push`, the upload has happened. A failed handler does not
undo it, and continuation does not repeat the completed upload. Native Git
push still decides whether a concurrent remote update permits publication.

## Fold events

`before-fold` and `after-fold` have only the `checkpoint` discriminator.
They surround the recursive pull's folding step; they do not identify an
individual splice. The saved continuation remembers the fold roots.

## Repository snapshot

| Field | JSON type | Meaning |
|---|---|---|
| `root` | string | Absolute monorepo working directory. |
| `git_dir` | string | Absolute Git directory for this worktree. |
| `head` | string | Monorepo HEAD at this handler call. |
| `branch` | string | Monorepo branch name. |
| `fetched_refs` | string | Snapshot of names and object IDs under `refs/splices/`. |
| `config` | string | Hash of effective Git configuration used as a continuation guard. |
| `fold_start` | string or null | Recorded `SPLICE_PULL_START` commit, if present. |

These fields are observations and guards. Editing them does not update the
repository. See [continuation validation](02-continue-from.md#repository-validation).

## Continuation state

Treat `continuation` as an opaque object, even though it is JSON. It contains
original options, discovery state, fetch failures, merge or push progress,
fold roots, and remaining handlers. Its `phase` identifies the next engine
step; it is not another hook event.

The remaining hook queue refers to committed configuration sources, and an
unfiltered pending event preserves entries a later scoped handler needs.
These are implementation state, not script commands or editable instructions.
A handler should select work using `operation`, `event` and `hook_scope`, then
return the saved object intact if it stops.

## Result

The default is:

```json
{"rebuilt_commit": null}
```

Only `push` at `after-rebuild` accepts a non-null `result.rebuilt_commit`.
Set it to a commit ID or ref, emit the whole modified payload, and exit
nonzero. On continuation the tool resolves and validates the replacement.
Its files must match the committed splice content; ancestry and force rules
follow [`--rebuilt-commit`](../02-rebuilt-commit.md). Replacement requires one
explicitly named splice, without `--all`.

Successful handler stdout is not parsed as a response. Returning a result at
another operation or checkpoint is refused. The
[edited rebuild scenario](../../../09-scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/edit-with-exec.md)
executes this handoff and records the edited history afterward with `pull --bump`.
