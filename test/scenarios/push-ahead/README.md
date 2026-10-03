# Scenario: push-ahead

Only the monorepo changed since the clone.

- **Monorepo (`vendor/a`)**: cloned at `seed`, then a local commit.
- **Upstream**: `seed`, unchanged.

## Output

`scenario_push_ahead` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_push_ahead
```
-->

```scrut
$ git splice status
ok   vendor/a -> main (push)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

`log` shows the commit a push would publish, and who wrote it:

```scrut
$ git splice log
===  vendor/a (main)
< e859a6b local change  (Test <test@example.com>)
```

`push` sends it. Nothing is written to the monorepo:

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed e859a6b to main
```

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```
