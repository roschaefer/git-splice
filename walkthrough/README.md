# Walkthrough

`just walkthrough` builds a throwaway monorepo in a temporary directory and
opens a shell in it. This page walks through every command there, in
order, with the output each one prints. CI runs this page with
[scrut](https://facebookincubator.github.io/scrut/), so the output is what
the current version prints (`just docs-check`).

What you get:

- `$WALKTHROUGH/monorepo`: the monorepo, on `main`. You start here.
- `$WALKTHROUGH/upstream/pkg-a.git` and `pkg-b.git`: bare repositories on
  the same machine that stand in for the subtrees' remotes. The walkthrough
  shell exports `$WALKTHROUGH`, so you can paste the commands below as they
  are. Output shows the path as `$WALKTHROUGH` too.
- `vendor/pkg-a`: a subtree whose remote has one commit the monorepo
  doesn't have yet. It's already fetched.
- `vendor/pkg-b`: only a remote so far. Its folder doesn't exist yet.
- `ghost`: a remote without a folder, like any other remote in your repo
  that isn't a subtree.

`simulate-remote-change <path> [message]` pushes a commit to a subtree's
remote, as if someone else had.

More walkthroughs, each starting from a fresh sandbox:

- [Feature branches](feature-branches.md): the remote branch follows your
  branch, and `push` creates it only where a subtree changed.
- [Diverged history](diverged.md): both sides changed the same line, and
  you resolve the conflict.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

## status

Lists every remote. A remote named like an existing folder is a subtree,
and gets its [sync state](../README.md#sync-states) and the files that
differ. `status` doesn't fetch; it uses what was fetched last.

```scrut
$ git subtrees status
??   ghost -> (no mapping)
??   vendor/pkg-b -> (no mapping)
ok   vendor/pkg-a -> $WALKTHROUGH/upstream/pkg-a.git (pull)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

## init

`vendor/pkg-b` has no folder yet, so it isn't a subtree. `init` adds the
remote's content there. The remote already exists; `init` would add it
otherwise.

```scrut
$ git subtrees init vendor/pkg-b "$WALKTHROUGH/upstream/pkg-b.git"
===  vendor/pkg-b: fetching
ok   vendor/pkg-b fetched
===  vendor/pkg-b: adding subtree from $WALKTHROUGH/upstream/pkg-b.git
git fetch vendor/pkg-b main
From $WALKTHROUGH/upstream/pkg-b
 * branch            main       -> FETCH_HEAD
Added dir 'vendor/pkg-b'
ok   vendor/pkg-b: added
```

## fetch

Someone pushes to `pkg-b`'s remote. `fetch` fetches every subtree's remote
in parallel and calls out which branch moved.

```scrut
$ simulate-remote-change vendor/pkg-b "pkg-b: add a feature"
ok   vendor/pkg-b: pushed a new commit upstream ('pkg-b: add a feature')
     git subtrees status   # to see it
     git subtrees pull     # to bring it in
```

```scrut
$ git subtrees fetch
ok   vendor/pkg-a fetched
ok   vendor/pkg-b fetched (main moved 9b3cb02..b937c4f)
```

## merge

`merge` squash-merges what was fetched, without contacting the remote.
Like every command but `init`, it takes paths to limit it to some
subtrees.

```scrut
$ git subtrees merge vendor/pkg-a
Merge made by the 'ort' strategy.
 vendor/pkg-a/file.txt | 1 +
 1 file changed, 1 insertion(+)
ok   vendor/pkg-a: merged
```

## pull

`pull` is `fetch` and `merge` in one: this brings in the `pkg-b` change
fetched above.

```scrut
$ git subtrees pull
ok   vendor/pkg-a fetched
ok   vendor/pkg-a: nothing to pull
ok   vendor/pkg-b fetched
Merge made by the 'ort' strategy.
 vendor/pkg-b/file.txt | 1 +
 1 file changed, 1 insertion(+)
ok   vendor/pkg-b: pulled
```

## diff

A commit in the monorepo changes `vendor/pkg-a`, so its state becomes
`push`.

```scrut
$ echo "a local fix" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: a local fix"
```

```scrut
$ git subtrees status vendor/pkg-a
ok   vendor/pkg-a -> $WALKTHROUGH/upstream/pkg-a.git (push)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

`diff` shows what `push` would send, with paths relative to the subtree,
as the remote sees them.

```scrut
$ git subtrees diff
===  vendor/pkg-a
diff --git a/file.txt b/file.txt
index 29cb4e6..20c1cf9 100644
--- a/file.txt
+++ b/file.txt
@@ -1,2 +1,3 @@
 pkg-a: seed
 pkg-a: a second commit, after connecting
+a local fix
```

## push

`push` splits each changed subtree out of the monorepo's history and
pushes it to the branch named like yours.

```scrut
$ git subtrees push
git push using:  vendor/pkg-a main
To $WALKTHROUGH/upstream/pkg-a.git
   2db2a00..3549b62  3549b6217763c17429b62d22c3b945b83641a14c -> main
ok   vendor/pkg-a: pushed
ok   vendor/pkg-b: nothing to push
```

```scrut
$ git subtrees status
??   ghost -> (no mapping)
ok   vendor/pkg-a -> $WALKTHROUGH/upstream/pkg-a.git (up to date)
ok   vendor/pkg-b -> $WALKTHROUGH/upstream/pkg-b.git (up to date)
```

## prune

A branch appears on `pkg-a`'s remote and gets fetched, then someone
deletes it there. Its remote-tracking ref stays behind.

```scrut
$ git -C "$WALKTHROUGH/upstream/pkg-a.git" branch release-1 main
```

```scrut
$ git subtrees fetch vendor/pkg-a
ok   vendor/pkg-a fetched
```

```scrut
$ git -C "$WALKTHROUGH/upstream/pkg-a.git" branch -D release-1
Deleted branch release-1 (was 3549b62).
```

```scrut
$ git branch -r
  vendor/pkg-a/HEAD -> vendor/pkg-a/main
  vendor/pkg-a/main
  vendor/pkg-a/release-1
  vendor/pkg-b/HEAD -> vendor/pkg-b/main
  vendor/pkg-b/main
```

`prune` removes such stale refs for every subtree remote. `--dry-run`
only lists them.

```scrut
$ git subtrees prune --dry-run
Pruning vendor/pkg-a
URL: $WALKTHROUGH/upstream/pkg-a.git
 * [would prune] vendor/pkg-a/release-1
```

```scrut
$ git subtrees prune
Pruning vendor/pkg-a
URL: $WALKTHROUGH/upstream/pkg-a.git
 * [pruned] vendor/pkg-a/release-1
```
