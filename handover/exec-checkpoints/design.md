# Design direction and remaining decisions

## Agreed direction

Build an operation-checkpoint interface underneath `--exec`. A script receives
a structured payload with the context it needs and chooses which checkpoints
to act on. The interface should accommodate fetches as well as merges; an
after-merge-only build hook is not enough for the broader request.

Use TWO script outcomes:

- Zero: proceed.
- Nonzero: stop at this checkpoint.

When continuing from the emitted payload, resume AFTER the checkpoint script
that stopped. Do not invoke the same checkpoint again by default. This supports
a script that unconditionally emits its payload and exits nonzero, advancing
one checkpoint per invocation. It resembles Git's default `rebase --exec`
behaviour, which consumes a failed exec instruction.

The assistant initially suggested a third reserved exit status to distinguish
intentional pauses from failures. The user challenged this; we agreed that it
was unnecessary for the default contract. Do not silently reintroduce it.
Automatic retry could be a separate future option, like Git's
`--reschedule-failed-exec`, but is not required by the agreed default.

## Payload round trip

The intended caller-owned workflow is:

1. git-splice completes an operation and invokes the script with its payload.
2. The script writes the payload somewhere (e.g. stdout redirected to a file)
   and exits nonzero.
3. The caller inspects the repository, draws/compares a diagram, or fixes a
   failed build/download.
4. The caller gives the payload back to git-splice with `--exec` again.
5. git-splice continues to the next operation/checkpoint.

`--continue-from <file>` was an illustrative spelling proposed by the assistant,
not a finalized CLI decision. JSON on script stdin was proposed and accepted
in principle, but no exact schema was approved. Neither CLI nor schema exists.

This still needs continuation state. It is held in the payload/file supplied
by the caller rather than necessarily in a hidden git-splice state directory.
Repository state alone cannot distinguish checkpoint positions: a fetch might
change no refs; multiple phases can share HEAD; a merge can already have
succeeded when its script fails.

Illustrative context, not a normative schema:

```json
{
  "version": 1,
  "operation": "pull",
  "checkpoint": "after-fetch",
  "sequence": 3,
  "splice": {
    "path": "vendor/a",
    "upstream": "https://example.com/a.git",
    "old_synced_commit": "...",
    "target_commit": "..."
  },
  "repository": {
    "root": "/path/to/monorepo",
    "head": "..."
  }
}
```

Continuation also needs enough information to restore the operation: original
arguments/options, exact next phase, selected/pinned targets, remaining work,
recursive discovery/reload bookkeeping, fold start, and expected repository
state. These are requirements to analyze, not an instruction to serialize the
entire Repo object or every cache.

## Three motivating consumers

### Executable diagram documentation

Pause at each meaningful operation, return control, run `check-drawing` to
compare actual state with a diagram, then feed the payload back. It should
replace the current ref-recording/rewind/replay approach with stepping through
the real command. See the code map for existing docs/helpers.

### LFS

After Git commits are fetched but BEFORE a merge/checkout materializes files,
the script fetches LFS objects from the correct upstream and target commit.
The normal smudge filter can then use the local object cache.

The same applies to dynamically discovered nested splices and changed upstream
URLs. LFS work must happen before the parent merge if that parent itself brings
in LFS pointers under nested paths: think carefully about actual materialization
boundaries, not just logical splice names.

If the LFS script fails and the caller continues past it, the caller must first
complete/verify the download, or risk the original smudge failure. Do not claim
that continuation skipping a failed download guarantees success.

Existing splice push already invokes Git LFS's pre-push upload hook. Full LFS
support has extra cases, especially upstream `.lfsconfig` custom endpoints and
path-dependent configuration. The checkpoint interface enables integration;
it does not automatically solve all LFS configuration cases.

### Build checks

Run `make` or another build command after each applied splice merge. Stop with
the offending merge still applied. The caller fixes/verifies the build before
continuing, since the failed script is consumed by default.

Fetching alone does NOT change checked-out source. Running make after each
fetch usually repeats the same build; the first applied update that breaks
the build is identified after its merge. A before-first-merge baseline check
is useful, but whether it is automatic is still undecided.

## Relationship to --rebuilt-commit

The existing pattern is rebuild -> inspect/edit externally -> pass a commit
back with `push --rebuilt-commit` or `merge --rebuilt-commit`. That is a narrow
external handoff: the commit is the intermediate result; subcommand, path,
options, and repository supply the other context.

A general continuation payload could represent an after-rebuild checkpoint
and feed the same validated result into the push implementation. Preserve
the convenient flags; reuse underlying logic where sensible.

Important nuance: `merge --rebuilt-commit` imports changes from a supplied
commit; it does not currently resume a suspended merge. No rewrite of these
flags was implemented or explicitly required as the first milestone.

## Design work still needed

- Choose actual CLI and payload schema; version the wire format.
- Identify stable semantic checkpoints across operations. Fetch/merge/fold
  during pull are the first implementation focus, but the user wants a general
  interface that can eventually apply to other operations too.
- Model precise continuation without refetching already selected targets or
  replaying completed mutations. Remote branches can move between invocations.
- Preserve dynamic recursive discovery; do not freeze a queue so early that
  splices introduced by parent merges are missed.
- Determine per-upstream/per-member versus per-batch fetch checkpoints. Fetch
  currently groups shared URLs and runs jobs in parallel, so payload semantics
  and deterministic stepping need deliberate treatment.
- Separate hook stdout from ordinary command output so an emitted JSON payload
  can be redirected directly. Current git-splice status messages use stdout;
  subprocess Git output may too. Do not publish examples promising clean JSON
  stdout until both are handled. Alternatively a script can save stdin itself.
- Define validation for stale payloads, repository/branch mismatch, moved refs,
  malformed data, unknown versions, dirty files, conflict resolution, and user
  repair commits. Repairs must be compatible with continuation, but unrelated
  state changes should not silently redirect work.
- Decide whether scripts may mutate repository state on success, and how
  payload expectations are refreshed when they do. Scripts see the payload
  before running, so it describes pre-script state unless explicitly updated.
- Do not resume arbitrary command strings from an untrusted payload implicitly;
  the user proposed passing `--exec` again. Keep data separate from execution.
- Avoid deadlocks if scripts ignore stdin and payloads grow. Handle subprocess
  launch failures, broken pipes, and exit statuses cleanly.
- Explicit checkpoint stops differ from crashes/signals mid-operation, which
  might not emit a payload. Do not promise crash recovery from this feature.
- Existing conflict handling must continue to work. A conflict is not a
  successfully completed after-merge checkpoint; do not fold on a pause/failure.
- Fold policy after repair commits and the interaction with persistent
  `SPLICE_PULL_START` need care. The payload might carry the fold start, but no
  decision was made to remove or replace the existing pseudo-ref.
- `--recursive --rebase` support is explicitly deferred in issue #445 pending
  #437. Preserve existing behaviour and avoid inadvertently claiming support.

## Suggested meaningful validation

- Script receives parseable, versioned context and chooses checkpoints.
- `cat; exit 1` stepping progresses through fetch, merge, and fold boundaries
  without looping, duplicate merges, or extra refetches.
- Zero-returning scripts leave ordinary pull behaviour intact.
- Nonzero stops all dependent operations, returns failure, and prevents fold.
- Resume with the same script stops at the next checkpoint; completed work is
  not repeated, even if fetch was a no-op or a remote advanced during the pause.
- Build failure leaves its merge applied, reports remaining splices, and resumes
  after a user repair; baseline/no-op handling is specified and tested.
- Nested discovery, changed upstreams, removed splices, shared URLs, pins,
  rewritten upstreams, and normal conflict resolution retain correct semantics.
- LFS pre-materialization fetching works with a cold object cache; upstream and
  monorepo have different remotes; later normal push uploads required objects.
- Payload validation rejects stale/wrong-repository data without mutations.
- A docs scenario uses real pause/continue plus `check-drawing`, not rewinding
  refs to simulate stepping.
