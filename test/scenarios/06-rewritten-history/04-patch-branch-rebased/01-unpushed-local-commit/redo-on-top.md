# Redo the local change on top

The way out of the [same state](README.md), where `pull` refuses:
`git splice pull --rebase`, like `git pull --rebase`. It takes the
rebased branch in on top of *a*, the newest commit whose folder has
exactly the synced commit's files, and rebases *b* onto that pull with
`git rebase`. The folder then has exactly the rebased branch's files at
the pull, so the rebuild starts there, and the change goes upstream as
one commit on top of *n*. The old patches, *p* and *q*, stay dropped.

It rewrites the monorepo's branch, so it's for a branch nobody else has
yet: it refuses when a remote-tracking branch has *b*.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_unpushed_local_commit
```

```scrut
$ git splice pull --rebase vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled 63b44f3, and rebased 1 commit onto it
```

The pull comes before the local change now:

```scrut
$ git log --format=%s
local change
splice: pull vendor/a from patches at 63b44f3
add vendor/a
initial commit
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 83e98ce to patches
```

The rebased branch gets the change on top, and *p* and *q* stay
dropped:

```scrut
$ git -C "$UPSTREAM" log --format=%s patches
local change
other patch
patch, reworded upstream
seed
```

The monorepo now has the pull *x* on top of *a*, and *c*, the local
change rebased onto it. The push put *c'*, the rebuild's copy of *c*, on
top of *n*. Nothing leads to *p* or *q* any more. The push records
nothing, so U(H) is still *n*, the commit the pull took, until the next
pull:

<div align="center">

![The monorepo's a, x and c in a line, H and main at c, B at x; upstream, c prime on top of n on top of m on top of k: T, R and patches at c prime, U(H) and U(B) at n, main at m](redone-on-top.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/redone-on-top.drawio.svg" a=HEAD~2 x=HEAD~1 c=HEAD \
>   k=refs/splices/upstream/patches~3 m=refs/splices/upstream/patches~2 n=refs/splices/upstream/patches~1
ok   redone-on-top.drawio.svg: 7 commits, 10 arrows, 5 boxes, 1 lanes
```
-->
