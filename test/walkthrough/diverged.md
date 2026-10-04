# Diverged history

A splice has diverged when both the monorepo and the upstream changed it
since the last sync. This walkthrough, in the [sandbox](README.md), makes
both sides change the same line, then resolves the conflict.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

First, bring `vendor/pkg-a` up to date:

```scrut
$ git splice pull vendor/pkg-a
ok   vendor/pkg-a fetched
ok   vendor/pkg-a: pulled 703b936
```

## Both sides change

The monorepo and the upstream each append a line to the same file:

```scrut
$ echo "a local fix" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: a local fix"
```

```scrut
$ simulate-remote-change vendor/pkg-a "pkg-a: an upstream fix"
ok   vendor/pkg-a: pushed a new commit upstream ('pkg-a: an upstream fix')
     git splice status         # to see it
     git splice pull vendor/pkg-a   # to bring it in
```

Once fetched, `status` reports the splice as `diverged`, and `log` shows
both sides:

```scrut
$ git splice fetch
ok   vendor/pkg-a fetched (main moved 703b936..4527a78)
```

```scrut
$ git splice status
ok   vendor/pkg-a -> main (diverged)
 file.txt | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```

```scrut
$ git splice log
===  vendor/pkg-a (main)
< 2d02eb8 pkg-a: a local fix  (Walkthrough <walkthrough@example.com>)
> 4527a78 pkg-a: an upstream fix  (Walkthrough <walkthrough@example.com>)
```

## Pull first

`push` refuses to drop upstream's commit:

```scrut
$ git splice push vendor/pkg-a
!!   vendor/pkg-a: upstream has commits this branch lacks -- run 'git splice pull vendor/pkg-a' first
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
>>>>>>> 89201a2 (splice: pull vendor/pkg-a from main at 4527a78)
```

## Resolve and push

Resolve it as for any merge: keep both lines, then commit.

```scrut
$ printf '%s\n' "pkg-a: seed" "pkg-a: a second commit, after the clone" "a local fix" "pkg-a: an upstream fix" >vendor/pkg-a/file.txt
```

```scrut
$ git add vendor/pkg-a/file.txt && git commit -q --no-edit && git log --oneline -1
ccd9894 splice: pull vendor/pkg-a from main at 4527a78
```

Only the local fix is left to push. Upstream gets it as its own commit,
joined with upstream's fix by a merge:

```scrut
$ git splice push vendor/pkg-a
ok   vendor/pkg-a: pushed 610288c to main
```

```scrut
$ git -C "$WALKTHROUGH/upstream/pkg-a.git" log --graph --format=%s main
*   splice: pull vendor/pkg-a from main at 4527a78
|\  
| * pkg-a: an upstream fix
* | pkg-a: a local fix
|/  
* pkg-a: a second commit, after the clone
* pkg-a: seed
```

```scrut
$ git splice status
ok   vendor/pkg-a -> main (up to date)
```

If the two sides share no history at all, e.g. because the upstream was
rebuilt from scratch, `merge`, `pull` and `push` don't try to merge. They
print the commands to keep either side instead; see the
[`diverged-unrelated-history`](../scenarios/diverged-unrelated-history/README.md)
scenario.
