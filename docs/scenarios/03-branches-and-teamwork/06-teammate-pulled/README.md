# Scenario: teammate-pulled

Alice pulled a change into the splice and pushed the monorepo. Bob,
in this monorepo, pulled the monorepo with `git pull`, but hasn't fetched
the splice since. His `.splice` now names the commit Alice pulled, the
synced commit, which his clone doesn't have yet.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_teammate_pulled
```

```scrut
$ git log --format=%s
p: pull vendor/a
a: clone vendor/a
initial commit
```

Without the synced commit, there's nothing to compare with:

```scrut
$ git splice status
On branch main

  ?? synced commit b3a04cf isn't here  vendor/a  run 'git splice fetch vendor/a', or check that upstream has it
```

`diff`, `log`, `merge` and `push` say the same and stop:

```scrut
$ git splice push vendor/a
??   vendor/a: synced commit b3a04cf isn't here -- run 'git splice fetch vendor/a', or check that upstream has it
!!   Failed: vendor/a
[1]
```

A fetch gets it:

```scrut
$ git splice fetch vendor/a
ok   vendor/a fetched (main moved 2101c34..b3a04cf)
```

```scrut
$ git splice status
On branch main

  up to date  vendor/a
```

`git splice pull` fetches first, so it doesn't stop here. If upstream
doesn't have the synced commit any more, e.g. after a force-push and a
`gc`, the fetch can't get it, and `pull` and `push` print the ways to
[pick a side](../../06-rewritten-history/03-diverged-unrelated-history/README.md).
