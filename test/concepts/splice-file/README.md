# The `.splice` file

A folder is a splice because it has a `.splice` file, committed like any
other file. It names the upstream, and the upstream commit the folder
last matched, the synced commit U(H) of the
[sync model](../sync-model/README.md). That's all the state there is: a
clone of the monorepo has every splice, with nothing to set up.

```text
[splice]
	id = 9b2e41c07d5a8f36       # which splice this is, wherever it moves
	commit = 9bb866a3ba726f2229597a45e8ea3368f7e669a8 # the synced commit U(H)
[upstream "origin"]
	url = git@github.com:x/a.git
	default-branch = master     # only if it's named differently, see below
```

- **It's in Git's config format**, so `git config --file` reads it. Only
  the `.splice` committed in `HEAD` counts.
- **`clone` and `init` create it; `merge` and `pull` update it.** `push`
  does not change the monorepo, so it does not change `.splice`.
- **`default-branch` names the branch to follow** when it differs from
  the monorepo branch. For example, it can map monorepo `main` to
  upstream `master`
  ([example](../../scenarios/04-upstreams/01-default-branch/README.md)).
- **`default-pin` follows a tag or commit instead of a branch.** `pull`
  stays at that revision until `.splice` names another one, and `push`
  refuses there ([example](../../scenarios/04-upstreams/06-default-pin/README.md)).

The [design](../../../docs/design/README.md#the-splice-file) explains
each of these choices.

## Output

The walkthrough's [sandbox](../../../docs/sandbox.md), where
`vendor/pkg-a/` is behind its upstream by one commit.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../walkthrough/scrut-setup.sh"
```
-->

```scrut
$ cat vendor/pkg-a/.splice
[splice]
	id = 679c78b9916de804
	commit = 9bb866a3ba726f2229597a45e8ea3368f7e669a8
[upstream "origin"]
	url = https://git.example.com/pkg-a.git
```

`git config` reads it like any config file:

```scrut
$ git config --file vendor/pkg-a/.splice splice.commit
9bb866a3ba726f2229597a45e8ea3368f7e669a8
```

There's no Git remote, so nothing can push the monorepo to an upstream by
mistake:

```scrut
$ git remote
```

A pull records the new synced commit:

```scrut
$ git splice pull vendor/pkg-a >/dev/null && git show --format=%s -- vendor/pkg-a/.splice
splice: pull vendor/pkg-a from main at 703b936

diff --git a/vendor/pkg-a/.splice b/vendor/pkg-a/.splice
index 16b61ae..5635a7f 100644
--- a/vendor/pkg-a/.splice
+++ b/vendor/pkg-a/.splice
@@ -1,5 +1,5 @@
 [splice]
 	id = 679c78b9916de804
-	commit = 9bb866a3ba726f2229597a45e8ea3368f7e669a8
+	commit = 703b9360f7ac335a1134e9b5771a90a7c09ba39a
 [upstream "origin"]
 	url = https://git.example.com/pkg-a.git
```

A push sends the folder's files, without `.splice`:

```scrut
$ echo "a local fix" >>vendor/pkg-a/file.txt &&
>   git commit -qam "pkg-a: a local fix" &&
>   git splice push vendor/pkg-a >/dev/null
```

```scrut
$ ls -A vendor/pkg-a
.splice
file.txt
```

```scrut
$ git ls-tree --name-only splices/pkg-a/heads/main
file.txt
```
