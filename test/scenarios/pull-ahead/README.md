# Scenario: pull-ahead

The remote gained a commit since the subtree was added; the monorepo hasn't touched
the subtree path.

- **Monorepo (`vendor/a`)**: added at `seed`, no local changes since.
- **Remote**: `seed`, then one more commit (`upstream change`).
- **Common ancestor**: yes -- the add point (`seed`).

The scenario also fetches once during setup, so `refs/remotes/vendor/a/*`
already reflects the remote's new commit (mirroring what a real `status`
run needs, since `status` never fetches on its own).

## Output

`scenario_pull_ahead` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_pull_ahead
```
-->

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (pull)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

There's nothing to push, so `diff` shows nothing:

```scrut
$ git subtrees diff
```

```scrut
$ git subtrees pull
ok   vendor/a fetched
Merge made by the 'ort' strategy.
 vendor/a/file.txt | 1 +
 1 file changed, 1 insertion(+)
ok   vendor/a: pulled
```

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (up to date)
```
