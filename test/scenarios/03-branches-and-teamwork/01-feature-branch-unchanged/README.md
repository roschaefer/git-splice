# Scenario: feature-branch-unchanged

The monorepo is on a branch upstream doesn't have, and the splice didn't
change on it.

- **Monorepo (`vendor/a/`)**: cloned at `seed` on `main`, then the branch
  `feature`, with no changes under `vendor/a/`.
- **Upstream**: only `main`.

Without a `feature` branch upstream, `git-splice` compares with upstream's
default branch, `main`, as a PR would. `push` creates the branch only if
the PR would show changes. Here `main` has every commit, so starting a
feature branch doesn't spawn empty branches upstream.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_feature_branch_unchanged
```

```scrut
$ git splice status
On branch feature

  unchanged, no upstream branch  vendor/a
```

```scrut
$ git splice push vendor/a
ok   vendor/a: nothing to push (upstream has no 'feature' branch, and a PR to 'main' would show no changes)
```
