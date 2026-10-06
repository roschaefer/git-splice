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

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_pushed_then_changed
```

```scrut
$ git splice status
ok   vendor/a -> main (push: ahead 1)
```

```scrut
$ git splice log
===  vendor/a (main)
< 8b60a90 later change  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 8b60a90 to main
```

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```
