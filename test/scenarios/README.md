# Scenarios

Each folder here is one reusable test setup: a state a splice and its
upstream can be in, or a situation a command has to handle. A folder may
contain several Markdown documents, but each document explains and executes
one problem. `status`'s [sync states](../walkthrough/status.md#sync-states)
link to them as examples. Some show a bug as it is today; [Known
bugs](08-known-bugs.md) lists them.

The scenarios are grouped into numbered chapters by topic, from the
situations every user meets to the edge cases: everyday sync, starting a
splice, branches and teamwork, upstreams, nested splices, rewritten
history, and moved folders. Within a chapter, the numbers order the
scenarios the same way. The site drops the numbers from its URLs, and
takes a chapter's name from its `_category_.json`.

A scenario folder has:

- `setup.bash` defines one function, named after the folder without its
  number (`scenario_pull_ahead` in `01-pull-ahead/`). Given two paths, it builds a
  monorepo and a bare repository as its upstream in that state, out of the
  helpers in [`test/helpers/fixtures.bash`](../helpers/fixtures.bash). The
  bats tests and every document in the folder share that setup.
- Child folders, for scenarios that continue from this one. A child's
  `setup.bash` sources only its parent's, calls the parent's function, and
  adds its own steps: `02-up-to-date/02-push-ahead/` is `02-up-to-date/`
  plus one local commit. A scenario that continues from one in an earlier
  chapter sits at the top of its own chapter and sources that scenario's
  `setup.bash` instead: `03-branches-and-teamwork/01-feature-branch-unchanged/`
  builds on `01-everyday-sync/02-up-to-date/`. A document only calls its
  own folder's setup, so following the `source` lines shows every step.
- One or more `.md` files. Each describes one behavior and shows what the
  tool prints under "Output".

## Every scenario

This check lists every scenario folder, with how many documents it has.
It fails if a `setup.bash` sources anything but its parent's, or, at the
top of a chapter, more than one other scenario's, or doesn't define the
function named after its folder, or if a document doesn't link
to its setup or doesn't call that function first:

```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/readme-setup.sh" && check_scenario_setups
ok 01-everyday-sync/01-sync-model (1 document)
ok 01-everyday-sync/01-sync-model/01-after-pull (1 document)
ok 01-everyday-sync/01-sync-model/01-after-pull/01-pushed-and-bumped (1 document)
ok 01-everyday-sync/02-up-to-date (1 document)
ok 01-everyday-sync/02-up-to-date/01-pull-ahead (1 document)
ok 01-everyday-sync/02-up-to-date/02-push-ahead (1 document)
ok 01-everyday-sync/02-up-to-date/02-push-ahead/01-pushed-then-pulled (2 documents)
ok 01-everyday-sync/02-up-to-date/02-push-ahead/01-pushed-then-pulled/01-pushed-then-changed (1 document)
ok 01-everyday-sync/02-up-to-date/02-push-ahead/02-uncommitted-changes (1 document)
ok 01-everyday-sync/02-up-to-date/02-push-ahead/03-diverged-common-ancestor (1 document)
ok 01-everyday-sync/02-up-to-date/03-diverged-then-pulled (1 document)
ok 01-everyday-sync/03-many-splices (4 documents)
ok 01-everyday-sync/04-never-fetched (1 document)
ok 02-starting-a-splice/01-clone-copied-content (1 document)
ok 02-starting-a-splice/02-clone-differing-content (1 document)
ok 02-starting-a-splice/03-clone-on-feature-branch (1 document)
ok 02-starting-a-splice/04-init-new-upstream (1 document)
ok 02-starting-a-splice/04-init-new-upstream/01-removed-before-init (1 document)
ok 02-starting-a-splice/04-init-new-upstream/02-unspliced-then-cloned-again (1 document)
ok 02-starting-a-splice/05-init-then-cloned (2 documents)
ok 02-starting-a-splice/06-clone-without-commits (2 documents)
ok 02-starting-a-splice/07-submodule-in-linked-worktree (1 document)
ok 03-branches-and-teamwork/01-feature-branch-unchanged (1 document)
ok 03-branches-and-teamwork/01-feature-branch-unchanged/01-feature-branch-changed (1 document)
ok 03-branches-and-teamwork/01-feature-branch-unchanged/01-feature-branch-changed/01-stacked-branch (1 document)
ok 03-branches-and-teamwork/01-feature-branch-unchanged/02-merge-in-monorepo (2 documents)
ok 03-branches-and-teamwork/02-feature-branch-from-main (1 document)
ok 03-branches-and-teamwork/03-squash-merged-pull (1 document)
ok 03-branches-and-teamwork/03-squash-merged-pull/01-local-edit-in-the-squash (1 document)
ok 03-branches-and-teamwork/04-concurrent-pulls (3 documents)
ok 03-branches-and-teamwork/05-bisect-into-a-pull (1 document)
ok 03-branches-and-teamwork/05-bisect-into-a-pull/01-after-a-push (1 document)
ok 04-upstreams/01-default-branch (1 document)
ok 04-upstreams/02-several-upstreams (3 documents)
ok 04-upstreams/02-several-upstreams/01-original-without-the-patch (1 document)
ok 04-upstreams/03-shared-remote-url (1 document)
ok 04-upstreams/04-upstream-moved (1 document)
ok 04-upstreams/05-splice-refs (1 document)
ok 05-nested-splices/01-nested-splices (6 documents)
ok 05-nested-splices/01-nested-splices/01-outer-fork (3 documents)
ok 05-nested-splices/01-nested-splices/02-three-levels (1 document)
ok 05-nested-splices/02-nested-default-branch (1 document)
ok 06-rewritten-history/01-edited-before-push (2 documents)
ok 06-rewritten-history/02-upstream-rewritten-equal-tree (3 documents)
ok 06-rewritten-history/03-diverged-unrelated-history (1 document)
ok 06-rewritten-history/04-patch-branch-rebased (1 document)
ok 06-rewritten-history/04-patch-branch-rebased/01-unpushed-local-commit (1 document)
ok 06-rewritten-history/04-patch-branch-rebased/02-squash-merged (1 document)
ok 07-moved-folders/01-moved-with-unpushed-commits (2 documents)
ok 07-moved-folders/02-swapped-splices (1 document)
```

## The output is real

As on every page with output, [scrut](../../docs/sandbox.md#the-output-is-real)
runs the commands. Under "Output", each document first calls its
folder's scenario function, so it runs in the state the bats tests use:

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
4. Add a bats test that asserts the state, e.g. in `test/status.bats`.
