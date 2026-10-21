# Redo the local change on top

The way out of the [same state](README.md), where `pull` refuses: set
the unpushed change aside, pull the rebased branch, and redo the change
on top of it. The folder then has exactly the rebased branch's files at
the pull, so the rebuild starts there, and the change goes upstream as
one commit on top of *m*. The old patch, *p*, stays dropped.

`git splice pull --rebase` would do these steps
([#55](https://github.com/roschaefer/git-splice/issues/55)).

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

The unpushed changes are the ones since B, which `git splice boundary`
prints. Save them as a patch, with paths inside the folder:

```scrut
$ git diff --relative=vendor/a "$(git splice boundary vendor/a)" HEAD -- vendor/a >../local-change.patch
```

Set them aside: give the folder B's files again, except `.splice`, in a
commit of its own. `git restore` touches only the folder, unlike a
`git revert` of the commits, which would also undo their changes
elsewhere in the monorepo.

```scrut
$ git restore --source="$(git splice boundary vendor/a)" -- vendor/a ':!vendor/a/.splice' && git add -A vendor/a && git commit -q -m "vendor/a: set aside the unpushed changes"
```

Now the pull goes through:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled 97171d6
```

Redo the change, with the original commit's message and author, and
push it:

```scrut
$ git apply --directory=vendor/a ../local-change.patch && git add vendor/a && git commit -q -C HEAD~2
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed d1530f3 to patches
```

The rebased branch gets the change on top, and *p* stays dropped:

```scrut
$ git -C "$UPSTREAM" log --format=%s patches
local change
patch, reworded upstream
seed
```

The monorepo now has *s* (`vendor/a: set aside the unpushed changes`),
the pull *x*, and *c*, the change redone (`local change` again). The
push put *c'*, the rebuild's copy of *c*, on top of *m*. Nothing leads
to *p* any more. The push records nothing, so U(H) is still *m*, the
commit the pull took, until the next pull:

<div align="center">

![The monorepo's a, b, s, x and c in a line; upstream, c prime on top of m on top of k, with T and R at c prime](redone-on-top.drawio.svg)

</div>

The drawing shows what Git and `git-splice` say about it, with each
commit named by its place in the history
([`check_drawing`](../../../../../check-drawing/)):

```scrut
$ check_drawing "$TESTDIR/redone-on-top.drawio.svg" a=HEAD~4 b=HEAD~3 s=HEAD~2 x=HEAD~1 c=HEAD \
>   k=refs/splices/upstream/patches~2 m=refs/splices/upstream/patches~1
ok   redone-on-top.drawio.svg: 8 commits, 10 arrows, 4 boxes, 1 lanes
```
