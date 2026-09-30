# Scenario: pushed-then-changed

The monorepo pushed a change, then changed the subtree again. The remote
has nothing but that push.

- **Monorepo (`vendor/a`)**: added at `seed`, then a commit that was
  pushed with `git subtree push`, then another local commit.
- **Remote**: `seed`, then the commit `git subtree split` made from the
  pushed one.
- **Sync point**: still `seed` -- a push doesn't move it.

Compared with the sync point alone, both sides changed. But splitting
`HEAD` rebuilds the pushed commit exactly, so the remote's tip is an
ancestor of what `HEAD` would push, and a push fast-forwards the remote.

`common.bats` also covers what happens when someone else commits on the remote after that push:
`diverged`, or `pull` if the monorepo didn't change since its push.

## Output

`scenario_pushed_then_changed` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_pushed_then_changed
```
-->

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (push)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

```scrut
$ git subtrees push
git push using:  vendor/a main
To $UPSTREAM
   f0c70db..16a0bc6  16a0bc682abf86949d71796f5b7ef10f5304f267 -> main
ok   vendor/a: pushed
```

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (up to date)
```
