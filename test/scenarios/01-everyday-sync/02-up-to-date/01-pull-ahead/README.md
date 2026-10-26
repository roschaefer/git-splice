# Scenario: pull-ahead

Only upstream changed since the clone.

- **Monorepo (`vendor/a/`)**: *a* clones *k* (`seed`), no local changes since.
- **Upstream**: *k*, then *l* (`upstream change`), already fetched.

<div align="center">

![The monorepo commit a clones the upstream commit k, R; the upstream moved on to l, T](behind.drawio.svg)

</div>

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_pull_ahead
```

<!--
```scrut
$ k="$(git config --file vendor/a/.splice splice.commit)" &&
>   check_drawing "$TESTDIR/behind.drawio.svg" k="$k" a=HEAD l=splices/upstream/heads/main
ok   behind.drawio.svg: 3 commits, 4 arrows, 3 boxes, 1 lanes
```
-->

```scrut
$ git splice status
On branch main

  behind 1  vendor/a
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
On branch main

  up to date  vendor/a
```
