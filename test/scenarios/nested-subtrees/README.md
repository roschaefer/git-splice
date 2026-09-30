# Scenario: nested-subtrees

One subtree folder inside another: remotes `vendor/pkg` and
`vendor/pkg/extra`, both matching existing folders.

- **Monorepo**: `vendor/pkg` added at `seed`, then a folder
  `vendor/pkg/extra` with its own remote.
- **Remote**: one commit (`seed`). Both remotes point at it; only the
  names matter here.

Git 2.51+ refuses `git remote add vendor/pkg/extra` once `vendor/pkg`
exists, but older versions accept it, so the setup writes the remote to the
config directly.

Nesting breaks the tool's assumptions:

- `vendor/pkg`'s content includes `vendor/pkg/extra`, so it never matches
  its own remote and always looks like unrelated history.
- `refs/remotes/vendor/pkg/*` includes the inner remote's refs, so a
  never-fetched outer remote looks fetched.
- The recovery commands for unrelated history would `git rm -r vendor/pkg`
  (deleting the inner subtree) or force-push it with the inner subtree's
  files included.

The last point holds even if `vendor/pkg/extra` has no folder, so any remote
overlapping a subtree path is refused, not just two subtrees.

Removing the inner remote isn't enough on its own: `git remote remove
vendor/pkg/extra` keeps `refs/remotes/vendor/pkg/extra/*`, since the outer
remote's fetch refspec covers them too, and they'd then look like branches
of `vendor/pkg`. The error message includes the command that deletes them.

Every command fails before doing anything and prints the ways to fix it.
`git subtrees init` also refuses to register a nested remote (`init.bats`).

## Output

`scenario_nested_subtrees` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_nested_subtrees
```
-->

```scrut
$ git subtrees status
!!   nested subtrees are not supported: 'vendor/pkg' and 'vendor/pkg/extra' overlap -- fix it with one of:

  git remote remove vendor/pkg

  git remote remove vendor/pkg/extra
  git for-each-ref --format='delete %(refname)' refs/remotes/vendor/pkg/extra/ | git update-ref --no-deref --stdin

[1]
```
