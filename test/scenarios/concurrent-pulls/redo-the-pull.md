# Redo the pull

In the [same state](README.md), instead of resolving the conflict: abort
the merge, drop your own pull, update the monorepo, and pull the splice
again on top of the other developer's pull. That's simpler while your pull
is your only local commit, and keeps the history linear.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_concurrent_pulls
```

```scrut
$ git merge origin/main >/dev/null; git merge --abort
```

`--keep` drops the pull commit, and refuses if that would lose uncommitted
changes:

```scrut
$ git reset -q --keep HEAD~1 && git merge -q --ff-only origin/main
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled 4c1905d
```

```scrut
$ git log --format=%s
splice: pull vendor/a from main at 4c1905d
splice: pull vendor/a from main at 72efaac
splice: clone vendor/a from main at bde4164
initial commit
```

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```
