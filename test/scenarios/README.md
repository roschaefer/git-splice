# Scenarios

Each folder here is one reusable test setup: a state a splice and its
upstream can be in, or a situation a command has to handle. A folder may
contain several Markdown documents, but each document explains and executes
one problem. The root README's [sync states](../../docs/sync-states.md)
link to them as examples.

A scenario folder has:

- `setup.bash` defines one function, named after the folder
  (`scenario_pull_ahead` in `pull-ahead/`). Given two paths, it builds a
  monorepo and a bare repository as its upstream in that state, out of the
  helpers in [`test/helpers/fixtures.bash`](../helpers/fixtures.bash). The
  bats tests and every document in the folder share that setup.
- Child folders, for scenarios that continue from this one. A child's
  `setup.bash` sources only its parent's, calls the parent's function, and
  adds its own steps: `up-to-date/push-ahead/` is `up-to-date/` plus one
  local commit. A document only calls its own folder's setup, so following
  the `source` lines upward shows every step.
- One or more `.md` files. Each describes one behavior and shows what the
  tool prints under "Output".

## Table of contents

| Scenario folder | Documents |
| --- | --- |
| [`clone-copied-content`](clone-copied-content/) | [Clone copied content](clone-copied-content/README.md) |
| [`clone-differing-content`](clone-differing-content/) | [Clone differing content](clone-differing-content/README.md) |
| [`clone-on-feature-branch`](clone-on-feature-branch/) | [Clone on a feature branch](clone-on-feature-branch/README.md) |
| [`clone-without-commits`](clone-without-commits/) | [Clone without commits](clone-without-commits/README.md); [Ref-friendly path](clone-without-commits/ref-friendly-path.md) |
| [`concurrent-pulls`](concurrent-pulls/) | [Concurrent pulls](concurrent-pulls/README.md); [Redo the pull](concurrent-pulls/redo-the-pull.md); [Committed conflict markers](concurrent-pulls/committed-conflict-markers.md) |
| [`default-branch`](default-branch/) | [Default branch](default-branch/README.md) |
| [`init-new-upstream`](init-new-upstream/) | [Initialize a new upstream](init-new-upstream/README.md) |
| [`init-then-cloned`](init-then-cloned/) | [Init, then cloned](init-then-cloned/README.md); [Push before the fetch](init-then-cloned/push-before-fetch.md) |
| [`nested-splices`](nested-splices/) | [Nested splices](nested-splices/README.md) |
| [`never-fetched`](never-fetched/) | [Never fetched](never-fetched/README.md) |
| [`splice-refs`](splice-refs/) | [How commands change a splice's refs](splice-refs/README.md) |
| [`up-to-date`](up-to-date/) | [Up to date](up-to-date/README.md) |
| [`up-to-date/diverged-then-pulled`](up-to-date/diverged-then-pulled/) | [Diverged, then pulled](up-to-date/diverged-then-pulled/README.md) |
| [`up-to-date/feature-branch-unchanged`](up-to-date/feature-branch-unchanged/) | [Unchanged feature branch](up-to-date/feature-branch-unchanged/README.md) |
| [`up-to-date/feature-branch-unchanged/feature-branch-changed`](up-to-date/feature-branch-unchanged/feature-branch-changed/) | [Changed feature branch](up-to-date/feature-branch-unchanged/feature-branch-changed/README.md) |
| [`up-to-date/feature-branch-unchanged/merge-in-monorepo`](up-to-date/feature-branch-unchanged/merge-in-monorepo/) | [`git subtree` merge](up-to-date/feature-branch-unchanged/merge-in-monorepo/README.md); [Repeated `main` merges](up-to-date/feature-branch-unchanged/merge-in-monorepo/multiple-main-merges.md) |
| [`up-to-date/pull-ahead`](up-to-date/pull-ahead/) | [Pull ahead](up-to-date/pull-ahead/README.md) |
| [`up-to-date/push-ahead`](up-to-date/push-ahead/) | [Push ahead](up-to-date/push-ahead/README.md) |
| [`up-to-date/push-ahead/diverged-common-ancestor`](up-to-date/push-ahead/diverged-common-ancestor/) | [Diverged with a common ancestor](up-to-date/push-ahead/diverged-common-ancestor/README.md) |
| [`up-to-date/push-ahead/diverged-unrelated-history`](up-to-date/push-ahead/diverged-unrelated-history/) | [Diverged with unrelated history](up-to-date/push-ahead/diverged-unrelated-history/README.md) |
| [`up-to-date/push-ahead/moved-with-unpushed-commits`](up-to-date/push-ahead/moved-with-unpushed-commits/) | [Moved with unpushed commits](up-to-date/push-ahead/moved-with-unpushed-commits/README.md); [Push before moving](up-to-date/push-ahead/moved-with-unpushed-commits/push-before-moving.md) |
| [`up-to-date/push-ahead/pushed-then-pulled`](up-to-date/push-ahead/pushed-then-pulled/) | [Pushed, then pulled](up-to-date/push-ahead/pushed-then-pulled/README.md) |
| [`up-to-date/push-ahead/pushed-then-pulled/pushed-then-changed`](up-to-date/push-ahead/pushed-then-pulled/pushed-then-changed/) | [Pushed, then changed](up-to-date/push-ahead/pushed-then-pulled/pushed-then-changed/README.md) |
| [`up-to-date/push-ahead/uncommitted-changes`](up-to-date/push-ahead/uncommitted-changes/) | [Uncommitted changes](up-to-date/push-ahead/uncommitted-changes/README.md) |
| [`up-to-date/shared-remote-url`](up-to-date/shared-remote-url/) | [Shared remote URL](up-to-date/shared-remote-url/README.md) |
| [`up-to-date/squash-merged-pull`](up-to-date/squash-merged-pull/) | [Squash-merged pull](up-to-date/squash-merged-pull/README.md) |
| [`upstream-rewritten-equal-tree`](upstream-rewritten-equal-tree/) | [Upstream rewritten to an equal tree](upstream-rewritten-equal-tree/README.md); [Keep the upstream's version](upstream-rewritten-equal-tree/keep-the-upstream-version.md); [`push --force` undoes the rewrite](upstream-rewritten-equal-tree/push-force-undoes-the-rewrite.md) |

This check verifies that every scenario folder and document is present in the
table of contents, that each `setup.bash` sources nothing but its parent's
and defines its expected scenario function, and that every document links
to and invokes its own folder's setup:

```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/readme-setup.sh" && check_scenario_setups
ok clone-copied-content (1 document)
ok clone-differing-content (1 document)
ok clone-on-feature-branch (1 document)
ok clone-without-commits (2 documents)
ok concurrent-pulls (3 documents)
ok default-branch (1 document)
ok init-new-upstream (1 document)
ok init-then-cloned (2 documents)
ok nested-splices (1 document)
ok never-fetched (1 document)
ok splice-refs (1 document)
ok up-to-date (1 document)
ok up-to-date/diverged-then-pulled (1 document)
ok up-to-date/feature-branch-unchanged (1 document)
ok up-to-date/feature-branch-unchanged/feature-branch-changed (1 document)
ok up-to-date/feature-branch-unchanged/merge-in-monorepo (2 documents)
ok up-to-date/pull-ahead (1 document)
ok up-to-date/push-ahead (1 document)
ok up-to-date/push-ahead/diverged-common-ancestor (1 document)
ok up-to-date/push-ahead/diverged-unrelated-history (1 document)
ok up-to-date/push-ahead/moved-with-unpushed-commits (2 documents)
ok up-to-date/push-ahead/pushed-then-pulled (1 document)
ok up-to-date/push-ahead/pushed-then-pulled/pushed-then-changed (1 document)
ok up-to-date/push-ahead/uncommitted-changes (1 document)
ok up-to-date/shared-remote-url (1 document)
ok up-to-date/squash-merged-pull (1 document)
ok upstream-rewritten-equal-tree (3 documents)
```

## The output is real

The output in a scenario's README isn't pasted in.
[scrut](https://facebookincubator.github.io/scrut/) runs every command
shown and compares what it prints. `just docs-check` does this for all
scenarios, in CI too, and `just docs-check --write` updates the READMEs
after an intended change.

Under "Output", each document first calls its folder's scenario function,
so it runs in the state the bats tests use:

    $ build_scenario scenario_pull_ahead

`build_scenario` runs the function with a monorepo and an upstream, hides
what it prints, and changes into the monorepo. It comes from
[`readme-setup.sh`](readme-setup.sh), which a block that GitHub doesn't
render sources first. That file also fixes the commit dates and ignores
your git config, so commit hashes are the same on every run. The splice is
`vendor/a` unless the document says otherwise, and the upstream's path
shows as `$UPSTREAM`.

## Adding a scenario

1. Create `<name>/setup.bash` with a function `scenario_<name>`, with `_`
   for `-`. If it continues from another scenario, create it inside that
   scenario's folder, source `../setup.bash` and call the parent's function
   first.
2. Write one `.md` file per behavior. Copy the "Output" start from another
   scenario at the same depth, change the function name, and add a `scrut`
   block per command with just its `$ ` line.
3. Add the folder and its documents to the table of contents.
4. Run `just docs-check --write` to fill in the output, and read it.
