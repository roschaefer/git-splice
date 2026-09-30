# Scenario: feature-branch-unchanged

The monorepo is on a feature branch the subtree's remote has never heard
of, and nothing under the subtree path has changed since the branch was
cut from `main`.

- **Monorepo (`vendor/a`)**: added at `seed` on `main`, then switched to
  a new `feature` branch with no further commits.
- **Remote**: only has `main`, at `seed`. No `feature` branch.

## Output

`scenario_feature_branch_unchanged` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_feature_branch_unchanged
```
-->

The scenario sets no base branch, so the commands pass `--base main`:

```scrut
$ git subtrees status --base main
ok   vendor/a -> $UPSTREAM (no 'feature' branch on remote; unchanged since 'main')
```

```scrut
$ git subtrees push --base main
ok   vendor/a: nothing to push (remote has no 'feature' branch; unchanged since 'main')
```
