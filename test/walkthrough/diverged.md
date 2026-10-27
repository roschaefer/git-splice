# Diverged history

A splice has diverged when both the monorepo and the upstream changed it
since the last sync. In this example, both sides change the same line, then
resolve the conflict. It uses the [walkthrough sandbox](README.md).

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

First, bring `vendor/pkg-a/` up to date:

```scrut
$ git splice pull -m "p: pull pkg-a" vendor/pkg-a
ok   vendor/pkg-a fetched
ok   vendor/pkg-a: pulled 703b936
```

<div align="center">

![The monorepo and pkg-a upstream are up to date on main](diverged-up-to-date.drawio.svg)

</div>

<!--
```scrut
$ source "$TESTDIR/../../check-drawing/check-drawing" && \
>   check_drawing "$TESTDIR/diverged-up-to-date.drawio.svg" p=HEAD s=refs/splices/pkg-a/heads/main
ok   diverged-up-to-date.drawio.svg: 2 commits, 2 arrows, 2 boxes, 1 lanes
```
-->

## Both sides change

The monorepo changes `vendor/pkg-a/`:

```scrut
$ echo "a local fix" >>vendor/pkg-a/file.txt && git commit -qam "f: a local fix"
```

<div align="center">

![The monorepo main has local fix f, ready to rebuild on upstream main](diverged-local-change.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/diverged-local-change.drawio.svg" \
>   p=HEAD~1 f=HEAD s=refs/splices/pkg-a/heads/main
ok   diverged-local-change.drawio.svg: 4 commits, 4 arrows, 2 boxes, 1 lanes
```
-->

The upstream also gets a new commit, changing the same file:

```scrut
$ git clone -q "$WALKTHROUGH/upstream/pkg-a.git" ../pkg-a &&
>   echo "pkg-a: an upstream fix" >>../pkg-a/file.txt &&
>   git -C ../pkg-a commit -qam "u: an upstream fix" &&
>   git -C ../pkg-a push -q
```

Fetch it into the monorepo:

```scrut
$ git splice fetch
ok   vendor/pkg-a fetched (main moved 703b936..5972aa1)
```

<div align="center">

![The monorepo main has local fix f while upstream main has upstream fix u; rebuilding f would start from their shared commit s](diverged.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/diverged.drawio.svg" s=refs/splices/pkg-a/heads/main~1
ok   diverged.drawio.svg: 5 commits, 5 arrows, 2 boxes, 1 lanes
```
-->

`status` now reports the splice as diverged, and `log` shows both sides:

```scrut
$ git splice status
On branch main

  ahead 1, behind 1  vendor/pkg-a
```

```scrut
$ git splice log
===  vendor/pkg-a (main)
< c4dcfe0 f: a local fix  (Walkthrough <walkthrough@example.com>)
> 5972aa1 u: an upstream fix  (Walkthrough <walkthrough@example.com>)
```

`log --graph` draws that right-hand side:

```scrut
$ git splice log --graph
===  vendor/pkg-a (main)
< c4dcfe0 (R) f: a local fix  (Walkthrough <walkthrough@example.com>)
| > 5972aa1 (T) u: an upstream fix  (Walkthrough <walkthrough@example.com>)
|/  
o 703b936 pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
```

## Pull first

`push` refuses to drop upstream's commit:

```scrut
$ git splice push vendor/pkg-a
!!   vendor/pkg-a: upstream has commits this branch lacks
!!   Failed: vendor/pkg-a
[1]
```

`pull` splices upstream's side in. The same line changed on both sides, so
it stops with a conflict, like any merge:

```scrut
$ git splice pull vendor/pkg-a
ok   vendor/pkg-a fetched
Auto-merging vendor/pkg-a/file.txt
CONFLICT (content): Merge conflict in vendor/pkg-a/file.txt
!!   vendor/pkg-a: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)
!!   vendor/pkg-a: pull failed
!!   Failed: vendor/pkg-a
[1]
```

```scrut
$ cat vendor/pkg-a/file.txt
pkg-a: seed
pkg-a: a second commit, after the clone
<<<<<<< HEAD
a local fix
=======
pkg-a: an upstream fix
>>>>>>> a3f4622 (splice: pull vendor/pkg-a from main at 5972aa1)
```

## Resolve and push

Resolve it as for any merge: keep both lines, then commit.

```scrut
$ cat >vendor/pkg-a/file.txt <<'EOF'
> pkg-a: seed
> pkg-a: a second commit, after the clone
> a local fix
> pkg-a: an upstream fix
> EOF
```

```scrut
$ git add vendor/pkg-a/file.txt && git commit -q --no-edit && git log --oneline -1
f428907 splice: pull vendor/pkg-a from main at 5972aa1
```

The pull joins the rebuilt local fix with the upstream fix. The splice is
now ahead by two commits and ready to push:

<div align="center">

![The resolved pull q on monorepo main rebuilds as a merge of local fix f prime and upstream fix u](diverged-after-pull.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/diverged-after-pull.drawio.svg" \
>   p=HEAD~2 f=HEAD~1 q=HEAD s=refs/splices/pkg-a/heads/main~1
ok   diverged-after-pull.drawio.svg: 7 commits, 8 arrows, 2 boxes, 1 lanes
```
-->

`log --graph` draws those commits down to their shared history:

```scrut
$ git splice log --graph
===  vendor/pkg-a (main)
<   24f2ae6 (R) splice: pull vendor/pkg-a from main at 5972aa1  (Walkthrough <walkthrough@example.com>)
|\  
< | c4dcfe0 f: a local fix  (Walkthrough <walkthrough@example.com>)
| o 5972aa1 (T) u: an upstream fix  (Walkthrough <walkthrough@example.com>)
|/  
o 703b936 pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
```


```scrut
$ git splice status
On branch main

  ahead 2  vendor/pkg-a
```

Upstream gets the local fix as its own commit, joined with upstream's fix
by a merge:

```scrut
$ git splice push vendor/pkg-a
ok   vendor/pkg-a: pushed 24f2ae6 to main
```

<div align="center">

![After push, pkg-a upstream main points to the same resolved merge rebuilt from the monorepo](diverged-after-push.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/diverged-after-push.drawio.svg" \
>   p=HEAD~2 f=HEAD~1 q=HEAD \
>   s=refs/splices/pkg-a/heads/main~2 u=refs/splices/pkg-a/heads/main^2
ok   diverged-after-push.drawio.svg: 7 commits, 8 arrows, 2 boxes, 1 lanes
```
-->

```scrut
$ git -C "$WALKTHROUGH/upstream/pkg-a.git" log --graph --format=%s main
*   splice: pull vendor/pkg-a from main at 5972aa1
|\  
| * u: an upstream fix
* | f: a local fix
|/  
* pkg-a: a second commit, after the clone
* pkg-a: seed
```

```scrut
$ git splice status
On branch main

  up to date  vendor/pkg-a
```

If the two sides share no history at all, e.g. because the upstream was
rebuilt from scratch, `merge`, `pull` and `push` don't try to merge. They
print the commands to keep either side instead; see the
[`diverged-unrelated-history`](../scenarios/06-rewritten-history/03-diverged-unrelated-history/README.md)
scenario.
