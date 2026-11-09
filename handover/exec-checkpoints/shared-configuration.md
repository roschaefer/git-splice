# Recursive committed configuration

The user explicitly authorized expanding #435 beyond its original "only data"
restriction: committed `.spliceconfig` may contain executable hooks and must
apply recursively to inner splices. Implementation: `2503c47`.

## Interface

- Git-config syntax: `[splice]` shared defaults and `[splice "pull"]` (or another
  command name) for command-specific defaults. Command-specific entries win at
  one directory; directories are inherited from root down to the target path.
- Keys map to supported CLI options, e.g. messageTemplate, branch, upstream,
  recursive, track, force, noForkPoint. Unsupported/unknown keys are ignored.
  Positional paths, continueFrom and rebuiltCommit are invocation inputs.
- Explicit CLI values override defaults. Explicit paths override a configured
  all default. CLI -m and --message-template override either configured message
  source. Contradictory explicit CLI flags must remain contradictory: never
  normalize --bump/--rebase or --track/--no-track by dropping the first CLI flag.
- Files are read from commits, never the index/worktree. Git-config includes
  are disabled; configuration inheritance is explicit through directory scope.
- Ordinary options override; exec handlers compose outermost first. Empty exec
  clears inherited handlers for a scope. Repeated exec adds handlers. Explicit
  CLI --exec replaces configured handlers for a fresh invocation.
- Configured commands run in the directory containing their configuration;
  CLI commands still run at repo root. Payload hook_scope identifies the scope.
  Fetch events are filtered to entries that inherit that particular handler.

Public guide: `docs/06-command-reference/12-configuration.md`.

## Architecture

- `src/config.rs`: Invocation remembers original CLI Args and accepted options;
  Configuration resolves typed defaults through the existing argument parser.
  It caches committed file lookups, parsed blob contents and hook presence in
  ExecutionContext. The boxed raw CLI Args have no further Invocation nesting.
- Repo::configure applies per-path settings; classify, merge/push progression,
  fetch planning/tracking and clone/init template handling use it. Changed flags
  reapply merge modes, but unchanged flags must preserve temporary internal
  mode changes (rebase's no-local-commit fallback relies on this).
- Non-rebase fetch/pull/push use the checkpoint event runner even without an
  initial handler, because fetched configuration may introduce handlers.
  Ordinary output stays on stdout without hooks; incoming hook detection runs
  before fetch reports so emitted continuation remains clean. Configured
  continuations always route normal output to stderr.
- For after-fetch, each scope looks first in the nearest fetched splice commit,
  then fetched ancestors, then local HEAD. Missing incoming config falls back
  to committed local policy. Incoming branches, tags and commit pins are covered.
- MergeProgress saves configuration identities as well as .splice blobs. A
  parent changing only a child's configuration triggers rediscovery/refetch.
  Configured recursion is expanded through each direct child so inner false
  can stop descent. Pending descendants are removed only for nonrecursive
  pull, never merge --all (which still visits its explicitly selected children).
- should_fold includes scoped recursive defaults, so configuration-only
  recursion gets the same folding behavior as the CLI.

## Hook continuation

Continuation now contains pending_hooks, pending_event and cli_hook. Each
configured handler is a descriptor `{commit, file, scope, index}` into the
Git-parsed committed configuration. Command strings are not restored from the
payload. Pending descriptors are captured before executing each handler; the
stopped handler is consumed and remaining handlers are run on continuation.
The original unfiltered event is retained, since a scoped handler's event may
omit entries needed by a later handler. Sequence counts handler invocations.

Configured continuations need no --exec. CLI continuations still require the
script again. Repository validation rejects committed .spliceconfig changes,
as it does .splice changes; non-config repair commits remain permitted for
fetch/pull, while push requires identical HEAD. Old payload fields have serde
defaults, preserving the existing CLI continuation path.

## Validation and boundaries

- Full regression run: 904 Bats tests and 48 Rust tests passed.
- Final focused configuration suite: 13 tests passed, including two subsequently
  added cases for fetched tags and Git boolean empty/valueless semantics.
- A focused checkpoint/config/pin run passed all 49 tests; the configured LFS
  scenario verifies a plain pull downloads before checkout and a plain push
  retains native LFS uploads. The affected merge/nested/track/upstream/config
  compatibility suite passed 227 tests after correcting initial regressions.
- Documentation: 153 documents / 1,850 successful testcases, 179 label pages,
  117 diagram placements. The trace example was updated for added config reads.
- Lint, formatting and current-system Nix flake checks passed.
- Logs: `/tmp/git-splice-config-final-tests.log`, `-final-docs.log`,
  `-shipping-focus.log`, `-final-focus.log`, `-final-committed-flake.log`.

No built-in `git splice lfs` command was added: the existing proof-of-concept
script can now be configured. Custom LFS endpoints/backfills remain as before.
Hooks still exist only for fetch/pull/push; scoped rebase is rejected in a
checkpoint operation. Persistent caching is not implemented. The config guide
states that committed/incoming upstream configuration executes automatically;
this is the user's explicitly requested policy, not an implicit trust prompt.
