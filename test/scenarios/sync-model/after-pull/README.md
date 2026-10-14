# Scenario: after-pull

A pull merged local commits that were never pushed. The pull's commit is
the newest that changed `.splice`, but the rebuild starts further back,
at B: the newest such commit whose folder is the upstream commit it
recorded, S
([sync model](../../../concepts/sync-model/README.md)). The commits are
named as in the drawing there:

<div align="center">

![The graphs after a pull: the pull commit e records n, so U is U(e), n; B stays at a, and S is U(a), k; R is e prime, a merge of the rebuilt d prime and n](after-pull.drawio.svg)

</div>

- **Monorepo (`vendor/a/`)**: cloned at k in a, then b and d change the
  folder, c changes another one. `git splice pull` then merges n in, as e.
- **Upstream**: k, then l, m and n. It has never seen b or d.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_after_pull
```

The drawing shows what Git and `git-splice` say about it. a and e aren't
subjects the drawing can show, so they're named by their place in the
history ([`check_drawing`](../../../helpers/drawing.bash)):

```scrut
$ check_drawing "$TESTDIR/after-pull.drawio.svg" a=HEAD~4 e=HEAD
ok   after-pull.drawio.svg: 12 commits, 17 arrows, 6 boxes, 2 frames
```

The monorepo, with e on top. a is the clone, `add vendor/a`:

```scrut
$ git log --format=%s
splice: pull vendor/a from main at df79a48
d
c
b
add vendor/a
initial commit
```

```scrut
$ git -C "$UPSTREAM" log --format='%h %s' main
df79a48 n
d34c417 m
5ba0fc7 l
ae8b31f k
```

### U

e is the newest commit that changed `.splice`. It records n as U:

```scrut
$ git log --first-parent -1 --format=%s -- vendor/a/.splice
splice: pull vendor/a from main at df79a48
```

```scrut
$ git log -1 --format='%h %s' "$(git config --file vendor/a/.splice splice.commit)"
df79a48 n
```

### B

But e's folder isn't n: it has b's and d's files too, which the upstream
lacks. A rebuild starting at e would send them as one commit, under e's
message:

```scrut
$ git diff --stat "$(git config --file vendor/a/.splice splice.commit)" HEAD:vendor/a -- ':!.splice'
 b.txt | 1 +
 d.txt | 1 +
 2 files changed, 2 insertions(+)
```

So the rebuild goes back to the commit before e that changed `.splice`.
All of them, newest first:

```scrut
$ git log --first-parent --format=%s -- vendor/a/.splice
splice: pull vendor/a from main at df79a48
add vendor/a
```

a's folder is the commit it recorded, k. It's `HEAD~4`:

```scrut
$ git diff --quiet "$(git config --blob 'HEAD~4:vendor/a/.splice' splice.commit)" HEAD~4:vendor/a -- ':!.splice' && echo "a's folder is k"
a's folder is k
```

So a is B, what `git splice boundary` prints, and k is S:

```scrut
$ git log -1 --format=%s "$(git splice boundary vendor/a)"
add vendor/a
```

The commits since B that change the folder are the ones the rebuild
copies, newest first:

```scrut
$ git log --first-parent --format=%s "$(git splice boundary vendor/a)"..HEAD -- vendor/a
splice: pull vendor/a from main at df79a48
d
b
```

### R

From B, the rebuild copies b and d on top of S, k, as b' and d', and
skips c. Then it copies e as e', a merge of d' and n, with e's message.
`log --graph` draws R and T down to n, where they meet. k shows up as
the parent of b':

```scrut
$ git splice log --graph vendor/a
===  vendor/a (main)
<   854864a (R) splice: pull vendor/a from main at df79a48  (Test <test@example.com>)
|\  
< | d4da194 d  (Test <test@example.com>)
< | 9ec734f b  (Test <test@example.com>)
o | ae8b31f k  (Test <test@example.com>)
 /  
o df79a48 (T) n  (Test <test@example.com>)
```

### After the push

The push sends b', d' and e', and T moves to e':

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 854864a to main
```

A pull right after it has nothing to bring in, and leaves `.splice` as it
was. So B is still a: every rebuild still walks from a, and rebuilds b',
d' and e' with the same hashes.

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: nothing to pull
```

```scrut
$ git log -1 --format=%s "$(git splice boundary vendor/a)"
add vendor/a
```

### After a bump

`git splice pull --bump` records e' as U, in a new commit:

```scrut
$ git splice pull --bump vendor/a
ok   vendor/a fetched
ok   vendor/a: bumped the synced commit to 854864a
```

Its folder is e', so it's the new B, e' is S, and rebuilds start there:

```scrut
$ git log -1 --format=%s "$(git splice boundary vendor/a)"
splice: bump vendor/a from main at 854864a
```
