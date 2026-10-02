# Scenarios

Each folder here is one state a splice and its upstream can be in, such as
"only upstream changed" or "both sides changed", or one situation a command
has to handle. The root README's [sync states](../../README.md#sync-states)
link to them as examples.

A scenario folder has two files:

- `setup.bash` defines one function, named after the folder
  (`scenario_pull_ahead` in `pull-ahead/`). Given two paths, it builds a
  monorepo and a bare repository as its upstream in that state, out of the
  helpers in [`test/helpers/fixtures.bash`](../helpers/fixtures.bash). The
  bats tests in `test/*.bats` call these functions to get into a state.
- `README.md` describes the state and why it matters, and shows what the
  tool prints there under "Output".

## The output is real

The output in a scenario's README isn't pasted in.
[scrut](https://facebookincubator.github.io/scrut/) runs every command
shown and compares what it prints. `just docs-check` does this for all
scenarios, in CI too, and `just docs-check --write` updates the READMEs
after an intended change.

Before the commands, a block that GitHub doesn't render calls the
scenario's function, so the README runs in the state the bats tests use:

    $ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_pull_ahead

[`readme-setup.sh`](readme-setup.sh) also fixes the commit dates and
ignores your git config, so commit hashes are the same on every run. The
splice is `vendor/a` unless the README says otherwise, and the upstream's
path shows as `$UPSTREAM`.

## Adding a scenario

1. Create `<name>/setup.bash` with a function `scenario_<name>`, with `_`
   for `-`.
2. Write `<name>/README.md`: copy the hidden block from another scenario,
   change the function name, and add a `scrut` block per command with
   just its `$ ` line.
3. Run `just docs-check --write` to fill in the output, and read it.
