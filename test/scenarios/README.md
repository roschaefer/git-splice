# Scenarios

Each folder here is one reusable test setup: a state a splice and its
upstream can be in, or a situation a command has to handle. A folder may
contain several Markdown documents, but each document explains and executes
one problem. The root README's [sync states](../../README.md#sync-states)
link to them as examples.

A scenario folder has:

- `setup.bash` defines one function, named after the folder
  (`scenario_pull_ahead` in `pull-ahead/`). Given two paths, it builds a
  monorepo and a bare repository as its upstream in that state, out of the
  helpers in [`test/helpers/fixtures.bash`](../helpers/fixtures.bash). The
  bats tests and every document in the folder share that setup.
- One or more `.md` files. Each describes one behavior and shows what the
  tool prints under "Output".

## Scenario setups and documents

Every setup implementation is linked directly here. Multiple document links
in a row demonstrate scenarios that share one setup.

| Scenario documents | Shared setup |
| --- | --- |
| [clone copied content](clone-copied-content/README.md) | [setup](clone-copied-content/setup.bash) |
| [clone differing content](clone-differing-content/README.md) | [setup](clone-differing-content/setup.bash) |
| [clone on a feature branch](clone-on-feature-branch/README.md) | [setup](clone-on-feature-branch/setup.bash) |
| [clone without commits](clone-without-commits/README.md); [ref-friendly path](clone-without-commits/ref-friendly-path.md) | [setup](clone-without-commits/setup.bash) |
| [external contributor workflow](copybara-contributor-workflow/README.md) | [setup](copybara-contributor-workflow/setup.bash) |
| [default branch](default-branch/README.md) | [setup](default-branch/setup.bash) |
| [diverged with a common ancestor](diverged-common-ancestor/README.md) | [setup](diverged-common-ancestor/setup.bash) |
| [diverged, then pulled](diverged-then-pulled/README.md) | [setup](diverged-then-pulled/setup.bash) |
| [diverged with unrelated history](diverged-unrelated-history/README.md) | [setup](diverged-unrelated-history/setup.bash) |
| [changed feature branch](feature-branch-changed/README.md) | [setup](feature-branch-changed/setup.bash) |
| [unchanged feature branch](feature-branch-unchanged/README.md) | [setup](feature-branch-unchanged/setup.bash) |
| [initialize a new upstream](init-new-upstream/README.md) | [setup](init-new-upstream/setup.bash) |
| [`git subtree` merge](merge-in-monorepo/README.md); [repeated `main` merges](merge-in-monorepo/multiple-main-merges.md) | [setup](merge-in-monorepo/setup.bash) |
| [nested splices](nested-splices/README.md) | [setup](nested-splices/setup.bash) |
| [never fetched](never-fetched/README.md) | [setup](never-fetched/setup.bash) |
| [pull ahead](pull-ahead/README.md) | [setup](pull-ahead/setup.bash) |
| [push ahead](push-ahead/README.md) | [setup](push-ahead/setup.bash) |
| [pushed, then changed](pushed-then-changed/README.md) | [setup](pushed-then-changed/setup.bash) |
| [shared remote URL](shared-remote-url/README.md) | [setup](shared-remote-url/setup.bash) |
| [squash-merged pull](squash-merged-pull/README.md) | [setup](squash-merged-pull/setup.bash) |
| [up to date](up-to-date/README.md) | [setup](up-to-date/setup.bash) |

This check sources every linked folder's `setup.bash`, verifies its expected
scenario function, and verifies every Markdown document links to and invokes
that shared setup:

```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/readme-setup.sh" && check_scenario_setups
ok clone-copied-content (1 document)
ok clone-differing-content (1 document)
ok clone-on-feature-branch (1 document)
ok clone-without-commits (2 documents)
ok copybara-contributor-workflow (1 document)
ok default-branch (1 document)
ok diverged-common-ancestor (1 document)
ok diverged-then-pulled (1 document)
ok diverged-unrelated-history (1 document)
ok feature-branch-changed (1 document)
ok feature-branch-unchanged (1 document)
ok init-new-upstream (1 document)
ok merge-in-monorepo (2 documents)
ok nested-splices (1 document)
ok never-fetched (1 document)
ok pull-ahead (1 document)
ok push-ahead (1 document)
ok pushed-then-changed (1 document)
ok shared-remote-url (1 document)
ok squash-merged-pull (1 document)
ok up-to-date (1 document)
```

## The output is real

The output in a scenario's README isn't pasted in.
[scrut](https://facebookincubator.github.io/scrut/) runs every command
shown and compares what it prints. `just docs-check` does this for all
scenarios, in CI too, and `just docs-check --write` updates the READMEs
after an intended change.

Before the commands, a block that GitHub doesn't render calls the folder's
scenario function, so every document runs in the state the bats tests use:

    $ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_pull_ahead

[`readme-setup.sh`](readme-setup.sh) also fixes the commit dates and
ignores your git config, so commit hashes are the same on every run. The
splice is `vendor/a` unless the README says otherwise, and the upstream's
path shows as `$UPSTREAM`.

## Adding a scenario

1. Create `<name>/setup.bash` with a function `scenario_<name>`, with `_`
   for `-`.
2. Write one `.md` file per behavior. Copy the hidden block from another
   scenario, change the function name, link its `setup.bash`, and add a
   `scrut` block per command with just its `$ ` line.
3. Run `just docs-check --write` to fill in the output, and read it.
