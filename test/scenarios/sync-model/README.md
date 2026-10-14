# Scenario: sync-model

The state the [README](../../../README.md) and the
[sync model](../../concepts/sync-model/README.md) draw: both sides moved
on since the clone, and nothing was pulled or pushed yet. The commits are
named as in the drawing:

<div align="center">

![Monorepo commits a to d, upstream commits k to n, and the rebuilt commits b prime and d prime on top of k: U(H) = U(B) = k](before-pull.drawio.svg)

</div>

- **Monorepo (`vendor/a/`)**: cloned at k in a, then b and d change the
  folder, c changes another one.
- **Upstream**: k, then l, m and n, fetched.

[after-pull](after-pull/README.md) continues with the pull.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_sync_model
```

The drawing shows what Git and `git-splice` say about it. a is the clone,
`add vendor/a`, which isn't a subject the drawing can show, so it's named
by its place in the history
([`check_drawing`](../../helpers/drawing.bash)):

```scrut
$ check_drawing "$TESTDIR/before-pull.drawio.svg" a=HEAD~3
ok   before-pull.drawio.svg: 10 commits, 13 arrows, 5 boxes, 1 frames
```

R and T have each moved on from k:

```scrut
$ git splice log --graph vendor/a
===  vendor/a (main)
< d4da194 (R) d  (Test <test@example.com>)
< 9ec734f b  (Test <test@example.com>)
| > df79a48 (T) n  (Test <test@example.com>)
| > d34c417 m  (Test <test@example.com>)
| > 5ba0fc7 l  (Test <test@example.com>)
|/  
o ae8b31f k  (Test <test@example.com>)
```
