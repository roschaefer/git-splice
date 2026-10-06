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

## Every scenario

This check lists every scenario folder, with how many documents it has.
It fails if a `setup.bash` sources anything but its parent's, or doesn't
define the function named after its folder, or if a document doesn't link
to its setup or doesn't call that function first:

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
ok nested-splices (2 documents)
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
3. Run `just docs-check --write` to fill in the output, including the
   new folder's line under "Every scenario", and read it.
