# Implementation progress

This supersedes the original handover's statement that implementation had not
started. The original research and design files are historical context.

## Implemented on this branch

- `git splice pull --exec <command>` runs a shell script from the repository
  root with a version 1 JSON payload on stdin. Normal output moves to stderr
  in exec mode; stdout is reserved for the script. A writer thread handles
  payload input so scripts that ignore stdin do not block the parent.
- Two outcomes: zero proceeds, nonzero stops and returns failure with completed
  Git work applied. The script can `cat; exit 1` or save stdin itself.
- `git splice pull --continue-from <file> --exec <command>` resumes AFTER the
  stopped checkpoint. `-` reads the payload from stdin. Options and selected
  targets come from the payload; scripts are never restored from data.
- Fetch batches, actual HEAD-changing merges, before-fold and after-fold are
  checkpoints. Shared upstream fetches stay parallel. Nested discovery and
  changed upstream URLs can trigger further fetch-batch checkpoints.
- `src/checkpoint.rs` contains the public payload context and a private durable
  continuation (arguments, merge-loop phase, discovery maps, failures and fold
  start). It does not serialize all Repo caches. `src/merge.rs::MergeProgress`
  makes merge/discover/reload positions explicit; ordinary merge/pull uses the
  same loop with no checkpoint context collection when exec is disabled.
- `src/pull.rs::fetch_for_pull` shares the initial fetch plan and failure
  diagnostics between ordinary and checkpoint-driven pulls.
- Continuation checks repository/worktree/branch identity, fetched refs,
  SPLICE_PULL_START and a digest of effective Git configuration. HEAD may
  advance through repair commits that do not change `.splice` files. A
  different history or changed splice configuration requires a fresh pull.
- Normal conflicts still use Git's existing conflict state and a fresh rerun
  after resolution. No payload is promised for a failed underlying Git command
  or an abrupt process termination. `--rebase` is explicitly refused with exec.
- Existing flags such as `--rebuilt-commit` have not been changed. CLI
  integration now covers standalone fetch and pull, including pull's nested
  fetch/merge/fold operations. Standalone clone, init, merge, push and rebuild
  do not yet accept these options.
- Help/reference pages and bash/zsh/fish completions are updated. jq was added
  to the dev shell and the older-Git compatibility test environment.
- Serde and serde_json are new dependencies; Cargo.lock preserves existing
  dependency versions while adding theirs.

## Documentation and tests

- `docs/tests/checkpoints.bats` has 12 tests covering round-trip stepping,
  no-op fetches, stdin continuation, scripts ignoring stdin, new splices,
  changed nested upstreams, build failure/repair, stale data, configuration and
  branch changes, conflicts, malformed payloads, and LFS downloads.
- The LFS example uses both the fetched target and the old synced commit. A
  cold cache can lack historical content needed by the first monorepo push,
  even when the new version checks out correctly. The test verifies the push
  and a colleague's ordinary clone against a separate monorepo remote.
  Fetching these two commits is an example, not a guarantee of backfilling
  every historical LFS object or custom upstream `.lfsconfig` handling.
- The recursive step-by-step scenario now executes the real paused command
  rather than recording, rewinding and replaying refs. `pause_pull` writes a
  new payload before replacing the previous one to avoid truncating its input.
- Scenario docs wrap Git to merge stderr/stdout and normalize output. Pause
  helpers deliberately use `command git` to keep the JSON output separate;
  `2>&1` on the helper captures diagnostics outside the payload redirection.
- The `step-a` drawing is checked after discovering/fetching the new splice,
  because its upstream commit is unavailable before that fetch. The e1 circle
  is now solid and the SVG was regenerated with the drawing dev shell.

## Initial implementation verification

- `just lint` and `just fmt-check` passed.
- Rust workspace tests passed (44 unit tests).
- All 77 existing nested-splice tests passed after the refactor.
- `just docs-check` passed: 152 documents, 1,890 testcases; diagram labels and
  placement passed too. The pull command reference was rechecked after the
  last help wording change (23 testcases).
- The modified SVG was re-exported through `check-drawing/check-export --write`
  in `nix develop .#drawings` and its export check passed.
- Final `just test` passed: 44 Rust tests and all 856 Bats tests, including all
  12 new checkpoint tests. Run it with inherited pager overrides unset:

  ```fish
  nix develop -c env -u GIT_PAGER -u PAGER just test
  ```

  This environment exports `GIT_PAGER=cat` and `PAGER=cat`. Four pager tests fail
  with those overrides on both the implementation and a fresh build of the
  unchanged pile/recursion base; all four pass when the overrides are removed.
  A clone test failed during an earlier heavily parallel run but passed on
  recheck and in the final full suite. No unrelated pager/clone code was changed.
- `nix flake check -L` passed on the current host, including package building
  with the new dependencies and the smoke check. Other architectures were not
  checked.
- Implementation commit: `7dd30da` (`feat(pull): add resumable execution checkpoints`).
  Handover updates are kept in a separate commit to make excluding this folder
  straightforward.
- Verification logs: `/tmp/git-splice-exec-final-tests.log` (final clean run),
  `/tmp/git-splice-exec-docs-check.log`, `/tmp/git-splice-exec-flake-check.log`.
  Earlier diagnostic logs also exist with the `git-splice-exec-` prefix. They
  are temporary files, not committed artifacts.

## Limits and next review points

- The payload wire format is draft. Its context is documented; continuation is
  intended to be passed back unchanged, not a public script-editing interface.
- Input payloads currently have a 16 MiB limit. Very large repositories could
  eventually need a more compact format or a different limit.
- A failed script is consumed, including failed downloads/builds. The caller
  must fix and verify before continuing. There is no automatic retry mode.
- Git configuration validation is deliberately strict, including effective
  global/environment configuration. It avoids resuming against changed target
  selection, but may reject otherwise harmless setting changes.
- Calls to checkpoint scripts are sequential even though fetch batches remain
  parallel. A fetch checkpoint represents a whole completed batch, not a pause
  between concurrent member jobs.
- Broader standalone operation integration, a rebuild handoff checkpoint, full
  LFS endpoint/configuration support, and recursive rebase remain future work.


## Follow-up: standalone fetch and user-defined report

The user requested a simple scenario demonstrating arbitrary script logic and
asked for standalone fetch support, specifically for LFS. The extension adds:

- `fetch --exec` / `fetch --continue-from` with `operation: "fetch"` and an
  after-fetch checkpoint before tracking changes. Continuation finishes tracking
  and failure reporting without repeating the fetch or stopped script.
- Shared fetch planning and tracking helpers preserve ordinary fetch behaviour.
  Payloads must be continued with their original operation; phase mismatches
  are rejected. Fetch retains its ability to run during an existing conflict.
- The new scenario `01-everyday-sync/05-exec-report` runs an external jq script
  with fetch and pull. It appends path/commit entries only after actual merges,
  demonstrating event selection and preventing duplicate report entries.
- Five new Bats cases cover fetch continuation, tracking/no-track, failure
  reporting, LFS download followed by a separate merge, and the report script.
- The LFS test confirms standalone fetch changes no checked-out files; its
  script populates the cache so the subsequent merge can materialize content.
- Fetch help, shared payload documentation, shell completions, scenario inventory
  and script lint/format checks are updated.

The focused checkpoint, tracking and upstream suite passed (62 tests).
Final verification for this follow-up:

- 44 Rust tests and all 861 Bats tests passed. Continue to unset inherited pager
  overrides when running `just test`, as described above.
- `just lint` and `just fmt-check` passed, including the new report script.
- `just docs-check` passed: 153 documents, 1,901 testcases, 172 prose-label pages
  and 131 diagram placements. The full docs run used four jobs to limit load
  while the test suite ran.
- `nix flake check -L` passed on the current host, including the package smoke test.
- Implementation commit: `c8755d9` (`feat(fetch): expose resumable execution checkpoints`).
- Logs: `/tmp/git-splice-fetch-exec-tests.log`,
  `/tmp/git-splice-fetch-exec-docs.log`, `/tmp/git-splice-fetch-exec-flake.log`.

## Follow-up: executable LFS proof of concept

The user asked to spike LFS support through the new interface and show the
impact of --exec in a scenario. No Rust/runtime changes were needed.

- Shared opt-in script: `docs/09-scenarios/04-upstreams/08-lfs-upstream/lfs-fetch.sh`.
  It ignores other events, downloads target and synced versions from each
  successful fetched entry's URL, and sends progress to stderr. Fetch include
  and exclude restrictions are cleared for these downloads. URL arguments are
  separated from options with `--`.
- A failed pipeline emits the complete original payload on stdout and exits 1.
  It does not invent a third hook outcome or retry automatically on continuation.
- Executable page:
  `docs/09-scenarios/04-upstreams/08-lfs-upstream/01-cloned-by-hand/01-retrained-upstream/with-exec.md`.
  It starts from the existing retrained-upstream fixture, shows plain pull's
  smudge failure, restores the files, then shows LFS fetching between Git fetch
  and merge. Version 2, clean status, normal push and a colleague's ordinary
  clone are verified. The existing known-bug page links to this opt-in example.
- The two existing LFS checkpoint tests now use this actual script instead of
  generating a separate inline implementation. An additional test removes the
  upstream LFS objects, checks the emitted payload and unchanged HEAD/index,
  restores the objects, explicitly reruns the downloader, and resumes the pull.
- The local LFS backend recreates an empty lfs/ directory during a missing-object
  request. The test restores by copying backup contents into it; moving the
  backup directory would nest it and leave the objects unavailable.
- Validation: all 18 checkpoint Bats tests passed, including the final failure
  test recheck; `just lint` and `just fmt-check` passed; `just docs-check` passed
  for 154 documents and 1,913 testcases (173 label pages, 131 placements).
  The complete 861-test Bats suite from the prior follow-up was not rerun for
  this script/docs-only change. There is now one additional Bats test.
- The prototype remains limited to ordinary upstream URL configuration. It does
  not add clone hooks, handle nested `.lfsconfig` endpoint selection, or perform
  a complete historical LFS-object migration.


## Rebase after the pile was rewritten

While the LFS prototype was being finished, pile/recursion was rewritten onto
`a6e89fc`. The draft PR consequently included old stack history. Only our seven
commits were replayed with `rebase --onto pile/recursion 8d56103`.

- Backup of the tested pre-rebase tip: local branch
  `backup/exec-checkpoints-lfs-spike` at `eb10885`.
- The sole conflict was `step-a.drawio.svg`: the new pile had independently
  made e1 solid. Both diagrams had the same semantic node style; the pile's
  already-exported SVG was retained.
- Rebased implementation commits are `155e9df` (pull), `f06bfa4` (fetch), and
  `a4698a3` (LFS prototype). Earlier hashes in this historical log refer to the
  backup history. Handover updates remain separate commits.
- All `src/`, checkpoint tests, and LFS scenario files are byte-identical to
  the tested pre-rebase tip. The base differences concern the drawing checker,
  drawing tests and recursion prose; no checkpoint/LFS code was changed.
- Lint, formatting and all 44 Rust tests passed after rebasing. Full executable
  documentation also passed against the updated drawing checker: 154 documents
  and 1,913 testcases.


## Requested rebase onto 60bdde9

PR #446 was subsequently rebased cleanly onto pile commit `60bdde9` by replaying
only its eight commits after `a6e89fc`. Range-diff matched all eight patches
before refreshing these handover notes. The pre-rebase tip is preserved as
`backup/exec-checkpoints-before-60bdde9` at `35001a3`.

Current implementation commits are `9bd8db7` (pull), `6033f73` (fetch), and
`04384f4` (LFS prototype). Earlier hashes above describe prior branch history.
Checkpoint/LFS source and tests are unchanged by this rebase. Lint, formatting,
and all 44 Rust tests passed on the new base. All 1,913 executable
documentation testcases and all 31 focused drawing/checkpoint Bats tests also
passed.
