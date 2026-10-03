# Scenario: feature-branch-unchanged

The monorepo is on a branch upstream doesn't have, and the splice didn't
change on it.

- **Monorepo (`vendor/a`)**: cloned at `seed` on `main`, then the branch
  `feature`, with no changes under `vendor/a`.
- **Upstream**: only `main`.

`push` creates a branch upstream only where a splice changed, so starting
a feature branch doesn't spawn empty branches upstream.

## Output

`scenario_feature_branch_unchanged` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_feature_branch_unchanged
```
-->

```scrut
$ git splice status
ok   vendor/a -> feature (upstream has no such branch; unchanged since 'main')
```

```scrut
$ git splice push vendor/a
ok   vendor/a: nothing to push (upstream has no 'feature' branch; unchanged since 'main')
```
