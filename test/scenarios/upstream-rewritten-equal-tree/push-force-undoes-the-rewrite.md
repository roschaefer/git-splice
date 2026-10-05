# `push --force` undoes the rewrite

In the [same state](README.md), after a local change, `git splice push
--force` makes the monorepo's side win. Its rebuild starts from the old
synced commit, so the upstream gets back the history the rewrite removed.
Don't use it when the rewrite removed something, like a secret;
[keep the upstream's version](keep-the-upstream-version.md) instead.

## Output

`scenario_upstream_rewritten_equal_tree` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_upstream_rewritten_equal_tree
```
-->

```scrut
$ echo "local change" >>vendor/a/file.txt && git commit -q -a -m "local change" && git splice push --force vendor/a
ok   vendor/a: pushed dea0473 to main
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
local change
release
seed
```
