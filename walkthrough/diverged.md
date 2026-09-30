# Diverged history

A subtree has diverged when both the monorepo and the remote changed it
since the last sync. This walkthrough, in the [sandbox](README.md), makes
both sides change the same line, then resolves the conflict.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

First, bring `vendor/pkg-a` up to date:

```scrut
$ git subtrees pull vendor/pkg-a
ok   vendor/pkg-a fetched
Merge made by the 'ort' strategy.
 vendor/pkg-a/file.txt | 1 +
 1 file changed, 1 insertion(+)
ok   vendor/pkg-a: pulled
```

## Both sides change

The monorepo and the remote each append a line to the same file:

```scrut
$ echo "a local fix" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: a local fix"
```

```scrut
$ simulate-remote-change vendor/pkg-a "pkg-a: an upstream fix"
ok   vendor/pkg-a: pushed a new commit upstream ('pkg-a: an upstream fix')
     git subtrees status   # to see it
     git subtrees pull     # to bring it in
```

Once fetched, `status` reports the subtree as `diverged`:

```scrut
$ git subtrees fetch
ok   vendor/pkg-a fetched (main moved 2db2a00..96a8153)
```

```scrut
$ git subtrees status vendor/pkg-a
ok   vendor/pkg-a -> $WALKTHROUGH/upstream/pkg-a.git (diverged)
 file.txt | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```

## Pull first

The remote refuses a push that would drop its commit:

```scrut
$ git subtrees push
git push using:  vendor/pkg-a main
To $WALKTHROUGH/upstream/pkg-a.git
 ! [rejected]        3549b6217763c17429b62d22c3b945b83641a14c -> main (non-fast-forward)
error: failed to push some refs to '$WALKTHROUGH/upstream/pkg-a.git'
hint: Updates were rejected because the tip of your current branch is behind
hint: its remote counterpart. If you want to integrate the remote changes,
hint: use 'git pull' before pushing again.
hint: See the 'Note about fast-forwards' in 'git push --help' for details.
!!   vendor/pkg-a: push failed
!!   Failed: vendor/pkg-a
[1]
```

`pull` squash-merges the remote's side. The same line changed on both
sides, so git stops with a conflict:

```scrut
$ git subtrees pull
ok   vendor/pkg-a fetched
Auto-merging vendor/pkg-a/file.txt
CONFLICT (content): Merge conflict in vendor/pkg-a/file.txt
Automatic merge failed; fix conflicts and then commit the result.
!!   vendor/pkg-a: pull failed -- resolve any conflicts, 'git commit', then re-run pull
!!   Failed: vendor/pkg-a
[1]
```

```scrut
$ cat vendor/pkg-a/file.txt
pkg-a: seed
pkg-a: a second commit, after connecting
<<<<<<< HEAD
a local fix
=======
pkg-a: an upstream fix
>>>>>>> 19a53603156c8f97afb99c1ab336081c0481fc7c
```

## Resolve and push

Resolve it as for any merge: keep both lines, then commit.

```scrut
$ cat >vendor/pkg-a/file.txt <<'EOF'
> pkg-a: seed
> pkg-a: a second commit, after connecting
> a local fix
> pkg-a: an upstream fix
> EOF
```

```scrut
$ git add vendor/pkg-a/file.txt && git commit --no-edit
[main 12f4691] Merge commit '19a53603156c8f97afb99c1ab336081c0481fc7c'
```

The merge commit contains the remote's side, so only the local fix is
left to push:

```scrut
$ git subtrees status vendor/pkg-a
ok   vendor/pkg-a -> $WALKTHROUGH/upstream/pkg-a.git (push)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

```scrut
$ git subtrees push
git push using:  vendor/pkg-a main
To $WALKTHROUGH/upstream/pkg-a.git
   96a8153..e6220d3  e6220d3065a466d29641e09a6dde23451bc734e2 -> main
ok   vendor/pkg-a: pushed
```

```scrut
$ git subtrees status vendor/pkg-a
ok   vendor/pkg-a -> $WALKTHROUGH/upstream/pkg-a.git (up to date)
```

If the two sides share no history at all, e.g. because the remote was
rebuilt from scratch, `merge`, `pull` and `push` don't try to merge. They
print the commands to keep either side instead; see the
[`diverged-unrelated-history`](../test/scenarios/diverged-unrelated-history/README.md)
scenario.
