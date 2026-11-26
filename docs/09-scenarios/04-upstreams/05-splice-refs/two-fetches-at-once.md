# splice-refs: two fetches at once

> **Limitation.** This page shows behaviour `git-splice` keeps on purpose, and the way out. See [known bugs and limitations](../../99-known-bugs.md#limitations).

Worktrees of one repository share its refs. Two fetches at the same time,
in two worktrees, may both try to move the same ref under
`refs/splices/`. Git lets one write at a time: the writer holds a lock
file next to the ref, and the other fails. Running it again fixes it, as
with two `git fetch` at once.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_splice_refs
```

The monorepo splices in the upstream. Someone pushes to the upstream's
`main`, with [`seed_bare_repo`](../../../tests/helpers/fixtures.bash):

```scrut
$ git splice clone https://git.example.com/a.git vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned bde4164 from main
```

```scrut
$ seed_bare_repo "$UPSTREAM" "upstream change"
```

A fetch in another worktree is writing `refs/splices/a/heads/main`, so
Git holds `main.lock` next to it. Here the lock file stands in for that
fetch:

```scrut
$ touch "$(git rev-parse --git-common-dir)/refs/splices/a/heads/main.lock"
```

A fetch here can't move the ref:

```scrut
$ git splice fetch
error: cannot lock ref 'refs/splices/a/heads/main': Unable to create '*/monorepo/.git/refs/splices/a/heads/main.lock': File exists. (glob)

Another git process seems to be running in this repository, or the lock file may be stale
!!   vendor/a fetch failed
!!   Failed: vendor/a
[1]
```

Once the other fetch is done, its lock is gone, and running the fetch
again moves the ref:

```scrut
$ rm "$(git rev-parse --git-common-dir)/refs/splices/a/heads/main.lock"
```

```scrut
$ git splice fetch
ok   vendor/a fetched (main moved bde4164..6045a98)
```
