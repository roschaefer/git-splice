# Code map and development workflow

All paths below are relative to this worktree. Locations were inspected at
base commit `8d56103`; line numbers will move during implementation.

## Entry points and shared infrastructure

- `src/main.rs`: dispatches subcommands. `rebuild` currently prints a commit
  identifier; `merge`, `pull`, `fetch`, `push` each call their own `run`.
- `src/lib.rs`: exports modules, also used by `check-drawing`.
- `src/args.rs`: shared `Args` (Default + Clone), allowed-option parsing.
  Value options are explicitly listed; currently upstream, rebuilt-commit,
  branch, message-template. Adding flags requires changing both parsing and
  the allowed options for each relevant command. No exec/continuation fields.
- `src/util.rs`: `Res<T> = Result<T, Fail>`; Fail variants are Soft, Hard,
  Code(i32). Many loops treat Soft as per-splice failure and keep going.
  `contained` converts Hard to Soft; be careful that checkpoint interruptions
  are not swallowed by existing error-handling paths.
- `src/util.rs`: `say`, `log_ok`, `log_step` write stdout. Warnings/errors write
  stderr. `git` wraps Command, supports stdin/env/capture. For supplied input,
  the capture path uses a writer thread to avoid pipe deadlocks.
- `src/repo.rs`: Repo contains arguments, discovery maps, keys, tracking,
  classification/rebuild caches, selected paths, merge options. Some fields
  are private and some OnceCells; no serialization is present. Serialize
  durable continuation meaning rather than reflexively deriving serde on Repo.
- `Cargo.toml`: package v0.20.0, edition 2021; currently NO dependencies.
  Workspace default members are root, check-drawing, check-help; scrut excluded.
  Serde/serde_json source versions exist in local cargo cache, but introducing
  them still needs Cargo.lock and Nix compatibility checks. No dependencies
  have actually been added.

## Pull flow

`src/pull.rs::run`:

1. Parse merge options plus `--recursive`, apply options, open Repo, validate
   message template and no splice conflict/rebase in progress.
2. Select splices; get monorepo branch, top-level selected splices, and all
   descendant splices (including unselected descendants).
3. Fetch used upstreams of top-level selections and every upstream of their
   descendants via `repo.fetch_all`.
4. Filter selected paths whose own/ancestor/descendant fetches failed.
5. For recursive non-rebase pulls, create pseudo-ref `SPLICE_PULL_START` at
   HEAD if it does not exist. NOTE this is currently AFTER the initial fetches.
6. `repo.merge_paths(branch, "pull", fetched)`; errors set status 1.
7. If folding applies and no conflict is in progress, fold only on status 0.
   The start ref is removed on success or certain fetch-failure paths.

`fold_pulls` in that file:

- Reads reverse first-parent commits in `SPLICE_PULL_START..HEAD`.
- Fewer than two: no fold.
- If any commit does not change a `.splice`, warns and leaves separate commits.
- Otherwise creates a commit with final tree and start as parent, then updates
  HEAD using expected-old-value protection.

## Merge loop and nested changes

`src/merge.rs::merge_paths` (around line 587):

- Top-down ordered path queue, `next` index, `failures`, `skipped`.
- `before` is HEAD at loop start. `loaded: HashMap<String, Option<String>>`
  tracks `.splice` blobs already loaded; initial values come from `before`.
- An in-progress conflict causes remaining paths to be skipped.
- Removed paths get skipped with a message; ancestor/descendant failures block
  dependent work.
- Calls `merge_one`, handles errors, optionally changes tracking.
- On success with no conflict, calls `discover_below` for recursion, inserts new
  paths into queue, then `read_below_again`.
- Prints "Not pulled yet"/"Failed" and returns Hard if incomplete.

`merge_one` classifies the splice, handles missing/no-op/equal-tree/bump states,
optionally rebases, checks target and merge base, and invokes `state::splice_in`.
It can return Ok without a new merge commit. Decide explicitly whether those
states generate a checkpoint; build checks should not accidentally repeat on
every already-synced splice during continuation.

`read_below_again` (around line 714): iterates descendants, compares current
`.splice` blob with last loaded blob, reloads changed configs and upstreams.
`reload_splice_upstream` (around line 515) compares old/new URLs, fetches newly
named upstreams, or fetches required ones when the synced commit/pin is absent.
These invoke `fetch_all` inside the merge loop. Suspending here requires keeping
enough loop/reload position to resume after the checkpoint, not just at the next
outer path.

`Repo::discover_below` and `discover_splices` are in `src/repo.rs`.

## Fetch implementation

`src/fetch.rs::Repo::fetch_all` (around line 201):

- Accepts `(path, upstream-name)` entries.
- Creates upstream keys before jobs start, groups by shared upstream URL/key.
- Builds jobs with URL/key, needed commits, and member metadata.
- Member includes path, target ref, old SHA, upstream branch, tag, report labels.
- Runs groups in parallel using scoped threads. Each group fetches all heads,
  required absent commits, and pins/tags. Fetched refs have reflogs; merge uses
  these to detect rewritten upstreams/fork points.
- Joins all jobs, prints reports in entry order, forgets newly-created keys for
  wholly failed jobs, and returns failed paths.

`fetch_upstream` fetches all heads into `refs/splices/<key>/heads/*` with prune,
no tags, no FETCH_HEAD, no recurse-submodules. `fetch_tag` preserves an already
fetched tag when it moves remotely. `fetch_by_id` fetches absent needed commits.

`used_upstream_entry` / `every_upstream_entry` construct entry lists. Standalone
`fetch::run` also applies track/no-track after fetching.

Checkpoint placement must consider parallel groups, shared URLs, no-op fetches,
tag/commit pins, and fetches inside recursive reload. A single checkpoint only
after the initial pull fetch is insufficient for LFS.

## Worktree materialization and rebuild handoff

- `src/state.rs::splice_in`: creates rerooted trees and throwaway commits, then
  invokes `git cherry-pick`. On conflict, leaves CHERRY_PICK_HEAD and instructs
  user to resolve and `git commit`. This is not `git merge`; a `post-merge`
  hook is not a general interception point here.
- `commit_state_files` uses a temporary index and `read-tree -m -u`, then commits
  state files. `src/clone.rs` also uses `read-tree` and `checkout-index` for some
  materialization. Do not assume porcelain checkout hooks cover these.
- `src/push.rs::give_rebuild` validates --rebuilt-commit: supplied commit exists,
  files match current splice content, synced ancestry unless forced, and the
  commit can later be recorded by pull. Push uses supplied history as-is.
- `src/usage/push.txt` and `src/usage/merge.txt` document the distinct handoffs.
  Merge's supplied commit is local work based on a rebuild; it imports changes
  with a three-way merge and leaves the synced upstream commit unchanged.

## Existing docs and tests to extend

- Issue #445 points to
  `docs/09-scenarios/05-nested-splices/05-recursion/01-recursive-pull/step-by-step.md`
  and that directory's `setup.bash` helpers `record_refs`, `rewind_refs`,
  `replay_refs`. These record reference-transaction events and simulate stepping.
  The issue requests using checkpoints to stop the real command instead.
- `docs/tests/nested.bats`: extensive nested behaviour coverage; reads scenario
  setup functions. Add meaningful checkpoint cases here or a focused bats file.
- `docs/tests/helpers/fixtures.bash`: hermetic configuration and Git helpers;
  binary under test defaults to `target/debug/git-splice` relative to worktree.
- `docs/09-scenarios/04-upstreams/08-lfs-upstream/`: executable scenario pages
  demonstrating failure, manual fetch/checkout, already-working push, and pull
  after upstream model retraining. These were also inspected in main.
- Help: `src/usage/pull.txt` mirrored through check-help into
  `docs/06-command-reference/05-pull.md`. Update both for new options. General
  operation support needs analogous command help/completion updates.
- Completions exist in `completions/` for bash, zsh, fish.

## Validation commands

Run from this worktree. These commands also work as typed in fish:

```fish
cargo build
cargo test --workspace --quiet
nix develop -c bats docs/tests/nested.bats
just lint
just fmt-check
just docs-check
```

`just test` builds, runs Rust tests and all bats tests. `just docs-check` builds
and checks diagram labels/placement, then runs scrut over the docs. Its recipe
accepts `--write` to update expected output. `just lint` runs clippy with
warnings denied and shellcheck. `just fmt-check` checks rustfmt and shfmt.
Nix's package build reads Cargo.lock, and source filesets include Cargo.toml,
Cargo.lock, src, checker sources, completions, LICENSE.

No checks have been run on implementation because no implementation exists.
