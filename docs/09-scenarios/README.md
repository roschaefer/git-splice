# Scenarios

Each scenario describes a situation, runs git-splice in it, and checks
what it prints. That makes the chapter
[specification by example](https://en.wikipedia.org/wiki/Specification_by_example)
and the acceptance tests of
[acceptance test-driven development](https://en.wikipedia.org/wiki/Acceptance_test-driven_development):
the documentation and the test are the same file. Some scenarios show a
bug or a limitation as it is today;
[Known bugs and limitations](99-known-bugs.md) lists them.

## Shared test setups

Each scenario folder builds one state of a monorepo and a bare upstream.
Its `setup.bash` defines a function named after the folder without its
number: `scenario_pull_ahead` in `01-pull-ahead/`. Given the two paths,
it builds that state out of the helpers in
[`fixtures.bash`](../tests/helpers/fixtures.bash).

A child folder continues from its parent: its `setup.bash` sources only
the parent's, calls its function, then adds steps.
`02-up-to-date/02-push-ahead/` is `02-up-to-date/` plus one local
commit. A scenario that continues from another chapter sits at the top
of its own chapter and sources that setup instead:
`03-branches-and-teamwork/01-feature-branch-unchanged/` builds on
`01-everyday-sync/02-up-to-date/`. Following the `source` lines shows
every step.

The same function builds the state for every test that needs it:

- The folder's documents call it first under "Output", through
  `build_scenario` (see [Scenario output](#scenario-output)).
- bats tests `load` the setup and call the function with temporary
  paths. [`status.bats`](../tests/status.bats) loads the setups of the
  sync states and checks the state each one shows.
- Rust tests source `fixtures.bash` and the setup in a `bash -c` script:
  [`tests/push.rs`](../../tests/push.rs) starts from
  `scenario_push_ahead`, and
  [`recursive_pull.rs`](../../check-drawing/tests/recursive_pull.rs)
  checks the drawings of `05-recursion/01-recursive-pull/`.

## Scenario output

Under "Output", each document first calls its folder's scenario
function, so it runs in the state the bats tests use. You can also
[explore scenarios in a sandbox](../01-getting-started/01-sandbox.md):

    $ build_scenario scenario_pull_ahead

`build_scenario` runs the function with a monorepo and an upstream, hides
what it prints, and changes into the monorepo. It comes from
[`readme-setup.sh`](readme-setup.sh). The splice is `vendor/a/` unless
the document says otherwise, and the upstream's path shows as
`$UPSTREAM`.

## Adding a scenario

1. Pick the chapter, and a number that puts the scenario between the
   more common and the rarer ones; renumber the folders after it. Create
   `<chapter>/<NN>-<name>/setup.bash` with a function `scenario_<name>`,
   with `_` for `-`. If it continues from a scenario in the same chapter,
   create it inside that scenario's folder, source `../setup.bash` and
   call the parent's function first. If that scenario is in another
   chapter, source its `setup.bash` by its path from `../../` instead.
2. Write one `.md` file per behavior. Copy the "Output" start from another
   scenario at the same depth, change the function name, and add a `scrut`
   block per command with just its `$ ` line.
3. Run `just docs-check --write` to fill in the output, including the
   new folder's line under "Every scenario". Read it: it's the
   documentation, so it has to say what the prose claims. Run
   `just docs-check` once more: output that differs between runs is a
   bug in the setup.
4. Add a bats test that asserts the state, e.g. in `docs/tests/status.bats`.

## Every scenario

This check lists every scenario folder, with how many documents it has.
It fails if a `setup.bash` sources anything but its parent's, or, at the
top of a chapter, more than one other scenario's, or doesn't define the
function named after its folder, or if a document doesn't link
to its setup or doesn't call that function first:

```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/readme-setup.sh" && check_scenario_setups
ok 01-everyday-sync/01-sync-model (1 document)
ok 01-everyday-sync/01-sync-model/01-after-pull (2 documents)
ok 01-everyday-sync/01-sync-model/01-after-pull/01-pushed (1 document)
ok 01-everyday-sync/01-sync-model/01-after-pull/02-pulled-again (1 document)
ok 01-everyday-sync/02-up-to-date (4 documents)
ok 01-everyday-sync/02-up-to-date/01-pull-ahead (1 document)
ok 01-everyday-sync/02-up-to-date/02-push-ahead (1 document)
ok 01-everyday-sync/02-up-to-date/02-push-ahead/01-pushed-then-pulled (3 documents)
ok 01-everyday-sync/02-up-to-date/02-push-ahead/01-pushed-then-pulled/01-pushed-then-changed (1 document)
ok 01-everyday-sync/02-up-to-date/02-push-ahead/02-uncommitted-changes (1 document)
ok 01-everyday-sync/02-up-to-date/02-push-ahead/03-diverged-common-ancestor (1 document)
ok 01-everyday-sync/02-up-to-date/03-diverged-then-pulled (1 document)
ok 01-everyday-sync/03-many-splices (6 documents)
ok 01-everyday-sync/04-never-fetched (1 document)
ok 01-everyday-sync/05-git-trace (1 document)
ok 02-starting-a-splice/01-clone-copied-content (1 document)
ok 02-starting-a-splice/02-clone-differing-content (1 document)
ok 02-starting-a-splice/03-clone-on-feature-branch (1 document)
ok 02-starting-a-splice/04-init-new-upstream (1 document)
ok 02-starting-a-splice/04-init-new-upstream/01-removed-before-init (1 document)
ok 02-starting-a-splice/04-init-new-upstream/02-unspliced-then-cloned-again (1 document)
ok 02-starting-a-splice/05-init-then-cloned (3 documents)
ok 02-starting-a-splice/06-clone-without-commits (2 documents)
ok 02-starting-a-splice/07-submodule-in-linked-worktree (1 document)
ok 02-starting-a-splice/08-clone-from-submodule (1 document)
ok 02-starting-a-splice/08-clone-from-submodule/01-submodule-without-branch (1 document)
ok 02-starting-a-splice/08-clone-from-submodule/02-submodule-with-branch (1 document)
ok 02-starting-a-splice/08-clone-from-submodule/03-submodule-with-branch-dot (1 document)
ok 02-starting-a-splice/08-clone-from-submodule/04-monorepo-line-endings (1 document)
ok 02-starting-a-splice/08-clone-from-submodule/05-line-endings-in-splice-above (1 document)
ok 02-starting-a-splice/08-clone-from-submodule/06-upstream-macro (1 document)
ok 02-starting-a-splice/08-clone-from-submodule/07-nested-submodules (1 document)
ok 02-starting-a-splice/09-clone-under-monorepo-attributes (1 document)
ok 03-branches-and-teamwork/01-feature-branch-unchanged (1 document)
ok 03-branches-and-teamwork/01-feature-branch-unchanged/01-feature-branch-changed (1 document)
ok 03-branches-and-teamwork/01-feature-branch-unchanged/01-feature-branch-changed/01-stacked-branch (1 document)
ok 03-branches-and-teamwork/01-feature-branch-unchanged/02-merge-in-monorepo (2 documents)
ok 03-branches-and-teamwork/01-feature-branch-unchanged/03-default-branch-moved (1 document)
ok 03-branches-and-teamwork/02-feature-branch-from-main (1 document)
ok 03-branches-and-teamwork/03-squash-merged-pull (1 document)
ok 03-branches-and-teamwork/03-squash-merged-pull/01-local-edit-in-the-squash (1 document)
ok 03-branches-and-teamwork/04-concurrent-pulls (3 documents)
ok 03-branches-and-teamwork/05-bisect-into-a-pull (1 document)
ok 03-branches-and-teamwork/05-bisect-into-a-pull/01-after-a-push (1 document)
ok 03-branches-and-teamwork/06-teammate-pulled (1 document)
ok 03-branches-and-teamwork/07-tracked-branch (1 document)
ok 03-branches-and-teamwork/08-bumped-on-a-feature-branch (2 documents)
ok 04-upstreams/01-default-branch (2 documents)
ok 04-upstreams/02-several-upstreams (4 documents)
ok 04-upstreams/02-several-upstreams/01-original-without-the-patch (1 document)
ok 04-upstreams/03-shared-remote-url (1 document)
ok 04-upstreams/04-upstream-moved (1 document)
ok 04-upstreams/05-splice-refs (3 documents)
ok 04-upstreams/06-default-pin (1 document)
ok 04-upstreams/07-contributing-through-a-fork (1 document)
ok 04-upstreams/08-lfs-upstream (2 documents)
ok 04-upstreams/08-lfs-upstream/01-cloned-by-hand (1 document)
ok 04-upstreams/08-lfs-upstream/01-cloned-by-hand/01-retrained-upstream (1 document)
ok 04-upstreams/09-encrypted-upstream (2 documents)
ok 05-nested-splices/01-nested-splices (12 documents)
ok 05-nested-splices/01-nested-splices/01-outer-fork (3 documents)
ok 05-nested-splices/01-nested-splices/02-three-levels (6 documents)
ok 05-nested-splices/02-nested-default-branch (1 document)
ok 05-nested-splices/03-diamond (1 document)
ok 05-nested-splices/04-cycle (1 document)
ok 05-nested-splices/05-recursion/01-recursive-pull (9 documents)
ok 06-rewritten-history/01-edited-before-push (2 documents)
ok 06-rewritten-history/02-upstream-rewritten-equal-tree (3 documents)
ok 06-rewritten-history/03-diverged-unrelated-history (2 documents)
ok 06-rewritten-history/04-patch-branch-rebased (2 documents)
ok 06-rewritten-history/04-patch-branch-rebased/01-unpushed-local-commit (1 document)
ok 06-rewritten-history/04-patch-branch-rebased/02-squash-merged (1 document)
ok 06-rewritten-history/05-pushed-then-rebased (1 document)
ok 07-moved-folders/01-moved-with-unpushed-commits (2 documents)
ok 07-moved-folders/02-swapped-splices (1 document)
ok 07-moved-folders/03-mirrors (2 documents)
ok 09-vcs-compatibility (1 document)
ok 09-vcs-compatibility/01-sapling-metadata (1 document)
ok 09-vcs-compatibility/02-sapling-git-index (1 document)
ok 09-vcs-compatibility/03-jujutsu-named-branch (1 document)
ok 10-platform-compatibility/01-platform-restrictions (2 documents)
```
