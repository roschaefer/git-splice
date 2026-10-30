# Development

With [Nix](https://nixos.org/download/) and
[flakes](https://wiki.nixos.org/wiki/Flakes), run in the clone:

    nix develop      # shell with the dev tools and this checkout on PATH
    just --list      # lint, fmt, test, ci, bench, sandbox, ...
    just sandbox     # try commands by hand in a throwaway monorepo
    just site-serve  # this documentation site, reloading on changes

[Writing the docs](writing.md) has the markup the documentation uses
for what, and [the design](design/README.md#architecture) where the state
lives.

Releases come from [release-please](https://github.com/googleapis/release-please):
it keeps a release PR open with the next version and changelog, built from
the Conventional Commits on `main`. Merging it tags and publishes the
release.

## Code map

`git-splice` checks the Bash and Git versions, sources `lib/*.sh`, and
dispatches `git splice <command>` to `cmd_<command>`. The libraries are
layered, each using only the ones above it:

| File | Responsibility |
|---|---|
| `lib/common.sh` | Discovery (`discover_splices`), argument parsing and path selection, reading and writing `.splice` (`splice_config`, `state_blob`), upstream keys (`upstream_key`, `create_upstream_key`), branch mapping. |
| `lib/rebuild.sh` | The push rebuild: `splice_last_sync`, `rebuild_splice`, `splice_start` (B) and the commit loop `rebuild_walk`. |
| `lib/state.sh` | `classify_splice`, the sync state every command acts on, and `splice_in`, the re-rooted cherry-pick behind `merge` and `clone --merge`. |
| `lib/pager.sh` | Paging for `diff` and `log`. |
| `lib/<command>.sh` | One command each: usage text, `cmd_<command>`, and its per-splice step. |

Each command follows the same shape: `select_paths` picks the splices,
then a per-splice function (`merge_one`, `push_one`, …) calls
`classify_splice` and acts on its state.

## Testing

Tests are executable documentation: a test's name states one behaviour,
and a scenario's README shows the tool's real output. Run them in
`nix develop`:

```
just test                 # bats tests
just docs-check           # concepts, scenario READMEs and walkthroughs, via scrut
just docs-check --write   # update them after an intended output change
just ci                   # lint, fmt-check, test, docs-check
```

CI also runs the whole suite on the oldest supported versions, Bash 4.4
and Git 2.40, and their newer counterparts.

### The layers

| Layer | Where | What it checks |
|---|---|---|
| Scenarios | `test/scenarios/**/setup.bash` | Nothing on its own: one function that builds a monorepo and an upstream in one state, nested under the scenario it continues from, or at the top of its chapter when that scenario is in an earlier chapter. Shared by everything below. |
| Command tests | `test/*.bats` | The `git-splice` CLI, run through the `splice` helper, against a scenario. |
| Oracle tests | `test/rebuild.bats` | The rebuild against `git subtree split`. |
| Scenario READMEs | `test/scenarios/**/*.md` | What the tool prints in that state, checked by scrut. |
| Walkthroughs | `test/walkthrough/*.md` | Every command once, in order, then a page per command, each on a fresh sandbox, checked by scrut. |
| Benchmark | `bench/`, `test/bench.bats` | `status` timings on a synthetic monorepo, reported on PRs out of draft. |

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
  `test/helpers/fixtures.bash`: `make_bare_repo`, `seed_bare_repo`,
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

### Writing a scenario

A scenario is one state a splice can be in, or one situation a command
has to handle. [Adding a scenario](../test/scenarios/README.md#adding-a-scenario)
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
