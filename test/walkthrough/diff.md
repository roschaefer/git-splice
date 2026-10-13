# diff

`git splice diff [--upstream <name>] [--base <branch>] [--stat] [path…]`

Shows what `push` would send: the changes from the fetched upstream
branch, T, to the rebuild, R, with paths as the upstream sees them.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice pull vendor/pkg-a >/dev/null
```

A commit in the monorepo changes `vendor/pkg-a/`:

```scrut
$ echo "a local fix" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: a local fix"
```

```scrut
$ git splice diff
===  vendor/pkg-a
diff --git a/file.txt b/file.txt
index 1b6c064..15c0cbd 100644
--- a/file.txt
+++ b/file.txt
@@ -1,2 +1,3 @@
 pkg-a: seed
 pkg-a: a second commit, after the clone
+a local fix
```

`--stat` summarizes the changes per file:

```scrut
$ git splice diff --stat
===  vendor/pkg-a
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```
