# Scenario: diverged-then-pulled

Both sides changed different files, then upstream's change was pulled in.
The local change is still waiting to be pushed.

- **Monorepo (`vendor/a/`)**: *a* clones *k* (`seed`), *b*
  (`local change`) adds `local.txt`, then *e*, a `git splice pull`,
  which merged cleanly.
- **Upstream**: *k*, then *l* (`upstream change`), which adds
  `upstream.txt`. It has never seen `local.txt`.

<div align="center">

![The monorepo commits a, b and the pull e, with B at a; upstream k and l, T; the rebuild b prime on top of k, and e prime, R, a merge of b prime and l](diverged-then-pulled.drawio.svg)

</div>

The pull's commit is the newest that changed `.splice`, but its folder
differs from the synced commit: it contains `local.txt`. So the boundary
stays the clone, and the push rebuilds the pull as a merge
of the local commit with upstream's, and the local commit keeps its own
identity upstream.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_diverged_then_pulled
```

<!--
```scrut
$ check_drawing "$TESTDIR/diverged-then-pulled.drawio.svg" \
>   a=HEAD~2 b=HEAD~1 e=HEAD \
>   k=splices/upstream/heads/main~1 l=splices/upstream/heads/main
ok   diverged-then-pulled.drawio.svg: 7 commits, 10 arrows, 4 boxes, 1 lanes
```
-->

```scrut
$ git splice status
On branch main

  ahead 2  vendor/a
```

```scrut
$ git splice log
===  vendor/a (main)
< 1c41ddd splice: pull vendor/a from main at 9887ec6  (Test <test@example.com>)
< c013d32 local change  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 1c41ddd to main
```

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s main
*   splice: pull vendor/a from main at 9887ec6
|\  
| * upstream change
* | local change
|/  
* seed
```
