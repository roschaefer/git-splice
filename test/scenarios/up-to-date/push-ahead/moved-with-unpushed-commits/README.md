# Scenario: moved-with-unpushed-commits

A splice with an unpushed commit is moved with `git mv`. The next push
sends the unpushed commit with its own message and author. The move
changes no file inside the folder, so it doesn't reach the upstream at
all.

- **Monorepo (`vendor/a/`)**: *a* (`add vendor/a`) cloned *k* (`seed`),
  then a local commit *b* (`local change`), not pushed yet.
- **Upstream**: *k*.

<div align="center">

![After the move m: the monorepo commits a, b and m, where m is H and a is B; in the lane libs/a/, R is b prime on top of k, and m has no copy](moved-with-unpushed-commits.drawio.svg)

</div>

`push` rebuilds the commits that changed the splice's folder. It follows
the folder through the move, by the splice's id, and rebuilds the commits
from before it under the old path. The move commit *m* (`reorganize
folders`) leaves `.splice` as it was, so it's no last sync: B is still
*a*, and R is *b'*, a copy of *b*. *m* changes no file inside the folder,
so it has no copy.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_moved_with_unpushed_commits
```

Before the move, the local commit is waiting to be pushed:

```scrut
$ git splice log
===  vendor/a (main)
< e859a6b local change  (Test <test@example.com>)
```

Someone else reorganizes the folders:

```scrut
$ git mv vendor/a libs/a && git -c user.name=Mover -c user.email=mover@example.com commit -q -m "reorganize folders"
```

The drawing shows what Git and `git-splice` say about it now
([`check_drawing`](../../../../../check-drawing/)):

```scrut
$ check_drawing "$TESTDIR/moved-with-unpushed-commits.drawio.svg" a=HEAD~2 b=HEAD~1 m=HEAD k=refs/splices/upstream/main
ok   moved-with-unpushed-commits.drawio.svg: 5 commits, 7 arrows, 4 boxes, 1 lanes
```

The local commit is still the one to push:

```scrut
$ git splice log
===  libs/a (main)
< e859a6b local change  (Test <test@example.com>)
```

```scrut
$ git splice push libs/a
ok   libs/a: pushed e859a6b to main
```

```scrut
$ git -C "$UPSTREAM" log --format='%s  (%an)' main
local change  (Test)
seed  (Test)
```

```scrut
$ git splice status
On branch main

  up to date  libs/a
```
