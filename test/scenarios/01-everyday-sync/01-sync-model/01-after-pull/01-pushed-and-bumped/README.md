# Scenario: pushed-and-bumped

The [parent scenario](../README.md) after `git splice push` and a
`git splice pull --bump`. The commits are named as in the drawing:

<div align="center">

![After the push and the bump: the bump commit f is H and B, U(H) = U(B) = e prime, and T and R point at e prime too](pushed-and-bumped.drawio.svg)

</div>

- **Monorepo (`lib/`)**: the parent scenario's commits, then *f*, the
  bump, which records *e'* in `.splice` and changes nothing else.
- **Upstream**: *k*, *l*, *m* and *n*, then the pushed *b'*, *d'* and *e'*.

The push made *b'*, *d'* and *e'* upstream commits, so they're drawn solid.
The bump made *f* the new B: its folder is *e'*, the commit it records. So
the rebuild starts at *f*, and has nothing to add: R = T = U(H) = U(B) = *e'*.
The U boxes show the sync points along the way: U(a) = *k* from the
clone, U(e) = *n* from the pull, and U(H) = U(B) = *e'* from the bump, *f*.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_pushed_and_bumped
```

<!--
```scrut
$ check_drawing "$TESTDIR/pushed-and-bumped.drawio.svg" a=HEAD~5 e=HEAD~1 f=HEAD
ok   pushed-and-bumped.drawio.svg: 13 commits, 16 arrows, 4 boxes, 1 lanes
```
-->

The monorepo, with *f* on top:

```scrut
$ git log --format=%s
splice: bump lib from main at 712cf4c
splice: pull lib from main at df79a48
d
c
b
add lib
initial commit
```

The upstream has the pushed commits, with the messages of *b*, *d* and *e*:

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s main
*   splice: pull lib from main at df79a48
|\  
| * n
| * m
| * l
* | d
* | b
|/  
* k
```

*f* is B:

```scrut
$ git log -1 --format=%s "$(git splice boundary lib)"
splice: bump lib from main at 712cf4c
```

And the splice is up to date:

```scrut
$ git splice status
On branch main

  up to date  lib
```
