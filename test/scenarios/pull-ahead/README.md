# Scenario: pull-ahead

Only upstream changed since the clone.

- **Monorepo (`vendor/a`)**: cloned at `seed`, no local changes since.
- **Upstream**: `seed`, then a commit, already fetched.

## Output

`scenario_pull_ahead` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_pull_ahead
```
-->

```scrut
$ git splice status
ok   vendor/a -> main (pull: behind 1)
```

```scrut
$ git splice log
===  vendor/a (main)
> 6045a98 upstream change  (Test <test@example.com>)
```

`merge` splices the change in as one ordinary commit, which also records the new synced commit in `vendor/a/.splice`:

```scrut
$ git splice merge vendor/a
ok   vendor/a: merged 6045a98
```

The monorepo's history stays linear, and upstream's commits never become part of it:

```scrut
$ git log --format=%s
splice: merge vendor/a from main at 6045a98
add vendor/a
initial commit
```

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```
