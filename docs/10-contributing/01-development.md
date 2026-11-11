# Development

With [Nix](https://nixos.org/download/) and
[flakes](https://wiki.nixos.org/wiki/Flakes), run in the clone:

    nix develop      # shell with the dev tools and this checkout on PATH
    just --list      # lint, fmt, test, ci, bench, sandbox, ...
    just sandbox     # try commands by hand in a throwaway monorepo
    just site-serve  # this documentation site, reloading on changes

[Writing the docs](02-writing.md) has the markup the documentation uses
for what, and [the design](../07-design/README.md#architecture) where the state
lives.

Releases come from [release-please](https://github.com/googleapis/release-please):
it keeps a release PR open with the next version and changelog, built from
the Conventional Commits on `main`. Merging it tags and publishes the
release.

## Code map

`src/main.rs` checks the Git version and dispatches `git splice <command>` to
the command's `run`. The tool only runs the `git` CLI, so
`GIT_TRACE=<absolute file> git splice <command>` lists every git command it runs
([how](../09-scenarios/01-everyday-sync/05-git-trace/README.md)).

| File | Responsibility |
|---|---|
| `src/util.rs` | Logging, failures (`Fail`) and running git. |
| `src/args.rs` | Argument parsing. |
| `src/execution.rs` | Typed fetch, merge, rebuild, push and fold observations for an optional execution-context observer. |
| `src/context.rs` | Caller-owned `ExecutionContext`: immutable content-tree cache, validated supplied rebuilds and optional progress observer shared by operations in one invocation. |
| `src/repo.rs` | `Repo`: discovery, path selection, reading `.splice`, upstreams, keys and what a splice syncs with. |
| `src/rebuild.rs` | The push rebuild: `rebuild_splice`, `splice_start` (B) and the commit loop `rebuild_walk`. |
| `src/state.rs` | `classify_splice`, the sync state every command acts on, and `splice_in`, the re-rooted cherry-pick behind `merge` and `clone`. |
| `src/pager.rs` | Paging for `diff` and `log`. |
| `src/<command>.rs` | One command each: its `run` and its per-splice step. |
| `src/usage/<command>.txt` | Each command's help. |

A failure is `Fail::Soft`, which ends one splice's step, or `Fail::Hard`, which
ends the command.

`main` creates one `ExecutionContext` and passes it as the first argument to
each command's `run`. A `Repo` borrows that context, so nested operations
share it. Mutable discovery, worktree observations and rebuild progress stay
on `Repo`; a new `Repo` reads current state while reusing tree-ID cache entries.
The context belongs to one invocation in one repository.

Rust callers can use `ExecutionContext::set_observer` to inspect synchronization
checkpoints from fetch, merge, pull and push. Callbacks run synchronously after
the completed step, before later work. Fetch observations include failed entries
and precede report/key cleanup and synced-history validation. Fold observations
surround the fold stage, before any subsequent rebase replay or cleanup.
An observer reports progress; it supplies no pause/cancel decision. The CLI
installs no observer. These Rust events do not define a serialized hook protocol.

For an in-memory push that can pause, Rust callers use `push::start` and keep its
`PushExecution`. `run_until` returns `ExecutionOutcome::Paused(event)` when its
predicate matches a named event. Calling `run_until` again continues after that
event; `run` completes the remaining work. An installed observer still receives
each event once. Completion retains the command's exit status, including failures.
Continuing requires the same working directory, Git directory, HEAD, branch,
fetched refs and effective Git configuration. The predicate must also preserve
that state. Uncommitted edits remain unpublished.
An error ends that execution. Dropping it abandons pending work and leaves completed
pushes applied; there is no saved continuation or CLI pause option yet.

To replay the in-memory push scenario and print diagrams checked against Git:

```sh
env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 cargo test --lib named_push_checkpoints -- --nocapture
```

Its setup declares each splice's path, empty upstream and committed files as
fixture values. Each printed diagram reads actual branch refs and verifies the
named local commits. `M` names the unchanged monorepo HEAD; `A` and `B` name the
rebuilt commits returned at the pauses. A dash means the upstream branch is
absent. Offline upstreams are renamed local test repositories; the inspector
reads their retained refs directly while the push still uses the missing URL.


Each command follows the same shape: `select_paths` picks the splices,
then a per-splice function (`merge_one`, `push_one`, …) calls
`classify_splice` and acts on its state.

## Testing

Tests are executable documentation: a test's name states one behaviour,
and a scenario's README shows the tool's real output. Run them in
`nix develop`:

```
just test                 # Rust unit tests, then bats tests
just docs-check           # concepts, scenario READMEs and walkthroughs, via scrut
just docs-check --write   # update them after an intended output change
just ci                   # lint, fmt-check, test, docs-check
```

CI also runs the bats tests on the oldest supported Git, 2.40.

### Which test to write

| What changed | Test |
|---|---|
| What a user sees: output, exit code, the repositories afterwards | A [bats test](#writing-a-bats-test), or a [scenario](#writing-a-scenario) if the output belongs in the docs |
| Logic with many edge cases that needs no repository: parsing, paths, quoting, messages | A [unit test](#writing-a-unit-test) next to the function |
| A bug | A bats test for the symptom the user saw, plus unit tests for the edge cases behind it |

The bats tests run the built binary and know nothing about its code, so
they kept checking the behaviour while the tool moved from shell to Rust.
Keep it that way: don't port them to Rust. They aren't slow because of
bats but because each builds repositories and runs Git, which a Rust
integration test would do too. A unit test needs neither and runs in
microseconds, so an edge case that fits one should not cost a repository.

### The layers

| Layer | Where | What it checks |
|---|---|---|
| Unit tests | `src/**/*.rs`, `check-*/src/*.rs` | Functions that need no repository, run by `cargo test`. |
| Scenarios | `docs/09-scenarios/**/setup.bash` | Nothing on its own: one function that builds a monorepo and an upstream in one state, nested under the scenario it continues from, or at the top of its chapter when that scenario is in an earlier chapter. Shared by everything below. |
| Command tests | `docs/tests/*.bats` | The `git-splice` CLI, run through the `splice` helper, against a scenario. |
| Oracle tests | `docs/tests/rebuild.bats` | The rebuild against `git subtree split`. |
| Scenario READMEs | `docs/09-scenarios/**/*.md` | What the tool prints in that state, checked by scrut. |
| Walkthroughs | `docs/01-getting-started/02-walkthrough.md`, `docs/06-command-reference/*.md` | Every command once, in order, then a page per command, each on a fresh sandbox, checked by scrut. |
| Benchmark | `bench/`, `docs/tests/bench.bats` | `status` timings on a synthetic monorepo, reported on PRs out of draft. |

### Writing a bats test

```bash
setup() {
  load 'helpers/fixtures'
  hermetic_git_config       # ignore the developer's git config
  load 'scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "push: writes nothing to the monorepo and creates no Git remote" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  …
}
```

- **Name the behaviour, not the steps:** `<command or function>: <what it
  does>`, e.g. `"status: a quiet splice with uncommitted
  changes moves up"`. The list of test names should read as a specification.
- **Start from a scenario** if one fits, so the test and the README show
  the same state. Otherwise build the state inline from the helpers in
  `docs/tests/helpers/fixtures.bash`: `make_bare_repo`, `seed_bare_repo`,
  `init_monorepo`, `add_splice`, `commit_local`, `fetch_splice`.
- **Fixtures don't use the code under test.** `add_splice` splices a
  folder in with raw plumbing, not `git splice clone`, so a bug in `clone`
  doesn't fail every other test. Use `splice <command>` (the real
  entrypoint) only where a state needs a command's own result, e.g. an
  earlier push.
- **Assert on Git's data, not only on output:** SHAs, trees, `rev-list`
  counts, whether a ref or a remote exists.
- **Make sure the test can fail.** A test that passes because both sides
  are empty, or because a step never ran, proves nothing. Check the
  precondition too, e.g. that the rebuild has three commits before
  comparing it.
- **A bug fix starts with a failing test** that reproduces it.

### Writing a unit test

A unit test lives in a `#[cfg(test)] mod tests` at the end of the module
it tests, as in `src/util.rs`:

```rust
#[test]
fn shell_quote_closes_and_reopens_the_quotes_around_a_single_quote() {
    assert_eq!(shell_quote("it's"), r"'it'\''s'");
}
```

- **Name the behaviour** as for bats, in snake case: the list of names
  should read as a specification.
- **Test functions that need no repository.** A function that runs Git is
  tested through the binary, by a bats test.
- **Make sure the test can fail:** break the function on purpose once and
  watch the test fail.

### Writing a scenario

A scenario is one state a splice can be in, or one situation a command
has to handle. [Adding a scenario](../09-scenarios/README.md#adding-a-scenario)
has the steps.

### `git subtree split` as the test oracle

`split` has years of fixes behind it, and the rebuild copies metadata the
same way. So on histories where both apply, the rebuild must produce
**identical SHAs**. That reuses `split`'s maturity in the tests without
running it in production.

To keep the comparison fair:

- Oracle fixtures are built with `git subtree add --squash`, which `split`
  understands, and the test passes B and U(B) to `rebuild_walk` directly.
- `.splice` stays out of oracle fixtures. `split` would include it in every
  tree, so its removal is tested separately.

**Approved divergences.** Where the rebuild deliberately differs from
`split`, the test asserts exactly how, and its name says
`approved divergence`:

1. **A merge in the monorepo becomes one commit.** Everything before the
   merge is identical; from the merge on, the SHAs differ:

   ```
   --- git subtree split (oracle):              --- first-parent rebuild:
   * 2098669 feature: after merge               * 4f27765 feature: after merge
   *   7584029 Merge branch 'main' into feature * 0f2628d Merge branch 'main' into feature
   |\                                           * 875a02b feature: g
   | * e6d52a2 main: h                          * e6d54f9 f2
   * | 875a02b feature: g                       * 9e9685e f1
   |/                                           * 153c9a7 up 1
   * e6d54f9 f2
   ```

2. **A squash-merged pull.** `split` rebuilds a duplicate of the upstream
   commit; the rebuild starts at the boundary and doesn't. Here the oracle
   is wrong. A rebased pull behaves the same way, and has a test of its
   own.

A new divergence needs a reason it's right, and a test like these.
