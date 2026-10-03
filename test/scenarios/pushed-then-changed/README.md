# Scenario: pushed-then-changed

The monorepo pushed a change, then changed the splice again. Upstream has
nothing but that push.

- **Monorepo (`vendor/a`)**: cloned at `seed`, a commit pushed with `git
  splice push`, then another local commit.
- **Upstream**: `seed`, then the pushed commit.
- **Synced commit**: still `seed` -- a push doesn't write to the monorepo.

The rebuild is deterministic, so it rebuilds the pushed commit exactly.
Upstream's tip is an ancestor of the rebuild, and the next push
fast-forwards it.

## Output

`scenario_pushed_then_changed` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_pushed_then_changed
```
-->

```scrut
$ git splice status
ok   vendor/a -> main (push)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

```scrut
$ git splice log
===  vendor/a (main)
< 16a0bc6 later change  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 16a0bc6 to main
```

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```
