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
  integration now covers fetch, pull and push, including pull's nested
  fetch/merge/fold operations and push's rebuild/upload stages. Standalone
  clone, init, merge and rebuild do not yet accept these options.
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

## Follow-up: push LFS changes to the splice upstreams

The user requested explicit upload coverage for the respective splice repos.
No production code or checkpoint script changes were needed: uploads already
use Git LFS's ordinary pre-push hook on the git push invoked by git-splice.

- The existing with-exec.md page now changes model.bin locally, commits it,
  runs `git splice push vendor/a`, and verifies version 3 in a fresh upstream
  clone. This tests new content, not a no-op push of objects upstream had already.
- New shared scenario:
  `docs/09-scenarios/04-upstreams/08-lfs-upstream/02-push-to-upstreams/`.
  Two upstreams each own a different model. After checkpoint-driven downloads,
  both models are edited locally and `git splice push --all` sends each change
  to its own upstream. Separate fresh clones verify distinct contents and no
  monorepo prefix/other-splice files. A monorepo push and plain colleague clone
  verify both models on that remote too.
- Both existing positive LFS checkpoint tests (pull and fetch followed by merge)
  now commit another local model change, push it upstream and verify a fresh
  clone. An additional test uses the new two-splice fixture.
- Validation: all 19 checkpoint Bats tests passed; `just lint` and
  `just fmt-check` passed; `just docs-check` passed for 155 documents and 1,925
  testcases, including 174 prose-label pages and 131 diagram placements.
- No Rust code changed. The full core test suite was not rerun for this
  scenario/test-only extension.


## Follow-up: push checkpoints and edited rebuilt-commit results

The user explicitly authorized extending PR #446 with push support and is
willing to tidy the larger PR later.

- `push --exec` / `push --continue-from` use the same runner and payload.
  `after-rebuild` exposes a prepared commit before upload; `after-push` follows
  upload, fetched-ref recording and attempted tracking. No-op pushes have no
  checkpoints. The queue remains bottom-up and failures block ancestors while
  independent splices continue.
- `src/push.rs::PushProgress` owns rebuild/publish phases, remaining paths,
  failures and supplied-history state. Ordinary push also uses this loop.
  `prepare_push` retains classification/rebuild checks; `publish_push` retains
  the ordinary native git push, LFS hooks, ref recording and bump reminder.
- The payload now has `result: {"rebuilt_commit": null}` (defaulted when absent
  for older payloads). At push's after-rebuild checkpoint, a script may emit a
  modified payload with a commit/ref in that field and exit nonzero. Continue
  resolves and validates it via the existing `give_rebuild` implementation.
  A zero-returning script does not replace the commit; stdout remains the
  script's own stream, not an automatically interpreted response channel.
- Replacement files must match committed splice content. Synced ancestry is
  required unless --force was in the original invocation; the existing checks
  against unrecordable/old history remain. Replacements are restricted to one
  explicitly named splice, like --rebuilt-commit, without --all. In particular,
  edited child history still needs the existing pull --bump handoff before
  proceeding with further work; the interface does not silently rewrite .splice.
- Push continuation requires exactly unchanged HEAD as well as the existing
  repository/worktree, branch, config and fetched-ref guards. The prepared commit
  stays pinned even if a ref originally passed with --rebuilt-commit moves.
  Results at other checkpoints/operations are refused. After-push pauses consume
  completed uploads, rather than replaying them.
- Event context exposes path, upstream name, URL, upstream branch, label, old
  fetched target, synced commit and rebuilt_commit. Push continuation is stored
  separately from merge progress in the shared continuation.
- Shared executable script/example:
  `docs/09-scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/reword-push.sh`
  and `edit-with-exec.md`. It edits the message of one rebuilt commit through
  commit-tree, returns result.rebuilt_commit, continues the push, and records
  the edited history with pull --bump. The test uses the actual example script.
- `docs/tests/push-checkpoints.bats` covers stepping before/after uploads,
  no duplicate push after pause, successful/invalid history replacement,
  force, no-ops, remote advancement, strict HEAD, results at wrong phases,
  dependent failures, tracking, pinned --rebuilt-commit refs, and single-splice
  replacement constraints.
- Existing LFS push scenarios and tests now invoke push --exec with the shared
  LFS script. It intentionally ignores push events; native pre-push uploads
  still work. CLI help/reference, common payload docs, shell completions and
  example-script lint/format checks are updated.

Verification passed: 873 Bats tests and 44 Rust tests; documentation checks
covered 156 documents, 1,939 testcases, 175 label pages and 131 placements.
Lint, formatting and `nix flake check -L` passed (current system).
Unset GIT_PAGER and PAGER for regression tests to avoid overriding pager fixtures.
Logs: `/tmp/git-splice-push-exec-final-tests.log`,
`/tmp/git-splice-push-exec-docs.log`, `/tmp/git-splice-push-exec-flake.log`.

Rebased onto pile commit `070e2ef` after the pile was rewritten again. Backup:
`backup/exec-checkpoints-before-070e2ef`. Preserved propagation of selected nested
paths and the stale SPLICE_PULL_START ancestry guard; applied the latter to
checkpoint pulls too. Removed a duplicate fish recursive completion introduced
by combining the two branches. Rebased verification logs use the prefix
`/tmp/git-splice-push-exec-rebased-`.

Final verification after the rebase passed: 879 Bats tests, 44 Rust tests,
lint, formatting, current-system Nix flake checks, and 155 documents with
1,927 successful testcases (175 label pages, 131 diagram placements).
The pile's Unicode-path folding fix also needed restoring after conflict
resolution; its new regression test caught the omission and now passes.
Implementation commits after rebase: `9cb7d9d` (push), `0a0f3e1` (stale fold
boundary integration), `cd83387` (Unicode folding integration). Prior tested
feature tip is retained by the backup branch above.

## Follow-up: explicit execution context

The user authorized refactoring all command signatures to pass execution context,
including read-only commands such as status. Implemented in `bddcffb`.

- `src/context.rs::ExecutionContext` starts empty at CLI dispatch. All command
  entrypoints take `&mut ExecutionContext` as their first argument.
- `Repo<'context>` borrows that context via `Repo::new(context, args)` instead of
  constructing its own calculation/override state. Its methods and recursive
  rebuild calls therefore share the same context without a second mutable borrow
  of it in every method signature. Drawing-checker call sites use explicit
  contexts too; Repo no longer implements Default.
- The context currently owns the existing immutable content-tree cache and
  validated supplied rebuilds. Both --rebuilt-commit and edited checkpoint
  results populate the latter through the existing validation path.
- Tree cache entries are keyed by the input Git tree ID, so hook checkpoints no
  longer clear them. Mutable working-tree observations are still cleared after
  hooks. A new Repo rereads command-specific discovery/configuration and owns
  its own classification and working-tree observations.
- Context lifetime is one execution; no disk cache, serialized cache, new hook
  phases, or status --exec was added. Existing continuation progress and JSON
  remain unchanged. Persistent rebuild caching still needs explicit input keys,
  object availability handling and repository scoping. Content-tree equality
  alone does not identify a history-producing rebuild: rewording can change
  rebuilt commits with the same tree. Classification already has its equal-tree
  fast path, which remains intact.
- The new shared-context Rust test exercises actual Git commits: an empty commit
  reuses tree results and the rebuild, changed content gets a new result, amended
  history with the same tree gets a different rebuild while retaining tree cache
  entries, status accepts the same context, and worktree checks are fresh across
  Repo handles.
- Verification: 879 Bats tests and 45 Rust tests passed; lint, formatting and
  current-system Nix flake checks passed. Documentation checks passed for 155
  documents and 1,927 testcases, plus 175 label pages and 131 placements.
  Logs use `/tmp/git-splice-context-{tests,docs,flake}.log`.
- The remote pile moved from 070e2ef to 710522e during this task, with substantial
  unrelated changes. This refactor remains on the previously verified 070e2ef
  base; it has not been rebased onto the newer pile during this task.

## Rebase onto main

See [main-rebase.md](main-rebase.md) for the exact base, backup, affected main
changes, dropped redundant fix, compatibility adaptations and verification.
This supersedes the previous note about remaining on the old pile base.

## Recursive executable .spliceconfig

See [shared-configuration.md](shared-configuration.md) for the authorized
execution policy, option precedence, recursive scope, incoming-source lookup,
continuation queue and verification. The implementation commit is `2503c47`.
This deliberately supersedes #435's original "only data" proposal, as requested
by the user, without adding new hook phases or a built-in LFS command.

## Configured LFS walkthrough and structured logging

The user requested updating the LFS prototype to exercise committed hooks,
adding a logging scenario, and linking all relevant foundations and scenarios
from the PR for later extraction of smaller changes. Implementation/documentation
commit: `e6e59fb`.

- Both LFS walkthroughs copy the downloader to `.splice-hooks/lfs-fetch.sh` and
  commit it with root `.spliceconfig`. Pull/push no longer repeat --exec.
- The single-splice walkthrough also publishes version 4 from a fresh upstream
  clone, demonstrates plain fetch leaving version 3 checked out, then plain
  merge materializing version 4. The colleague clone contains the handler and
  committed default. Test author identity is explicit for the upstream commit.
- The automatic-LFS Bats test now copies the handler into the repository and
  unsets CHECKPOINT_SCRIPT before pull/push, checking independence from the
  scenario-only script-path environment variable.
- `05-exec-report/logging.md` appends full payloads as JSON lines across fetch,
  pull and push, showing five events and per-invocation sequence numbers. A
  Bats regression checks event ordering, repository/continuation fields,
  successful publication and a clean worktree. No core Rust changed.
- The complete code/scenario navigation map is saved in `review-map.md` and
  added to the PR description using stable e6e59fb permalinks. It identifies
  context first-argument entrypoints, the context type, payload/event/result
  types, separate operation-progress queues, config implementation, LFS,
  logging/report/history-edit examples, and the live pause/tree-check/resume
  walkthrough (including its intermediate and final diagrams).
- Verification: both targeted Bats cases passed; full documentation checks
  passed for 154 documents / 1,869 testcases, 180 label pages and 117 placements.
  Full core tests were not rerun for these documentation/scenario-only changes.
  Documentation log: `/tmp/git-splice-hook-scenarios-docs.log`.

## Shared-option chapters and executable JSON payload

The user requested a docs-site chapter for --exec and its JSON payload, with a
scenario showing the payload, and shared references for --rebuilt-commit and
--recursive. Implemented in `8193f0c` without changing Rust or CLI behavior.

- Site hierarchy: Command reference -> Shared options -> --exec. The --exec
  index covers handler contracts/checkpoints/examples, with child pages for
  the full JSON field reference and --continue-from. Rebuilt-commit and
  recursive are sibling shared-option pages comparing command semantics.
- Command pages retain their executable help blocks and local examples, but
  link to canonical protocol pages instead of duplicating the payload schema
  mainly under pull. Existing per-command anchors remain available.
- `05-exec-report/payload.md` captures a complete real after-fetch payload,
  shows its keys and public JSON, checks the actual saved HEAD, resumes to an
  after-merge payload, checks actual before/after HEADs and file content, then
  resumes to completion without another payload. Stored payloads are untouched.
- Rendered projections explicitly replace temporary URLs/monorepo commit IDs
  with display labels and omit opaque continuation/guard strings. Initial full
  verification caught fixture-dependent monorepo IDs; the display now uses
  labels while assertions compare the real values. The display projection must
  never be fed back as a continuation.
- Verification passed: 155 documents / 1,883 executable cases, 187 label pages,
  117 diagram placements. Production site build passed with broken links and
  anchors configured to fail; all six reference pages and the normalized
  payload scenario were confirmed in website/build. No core tests were rerun
  for this documentation-only change.
- Logs: `/tmp/git-splice-shared-options-final-docs.log` and
  `/tmp/git-splice-shared-options-final-site.log`. Built pages are local artifacts;
  nothing was deployed to production. PR #446 remains draft.
