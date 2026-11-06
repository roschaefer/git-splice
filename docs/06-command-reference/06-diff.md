# diff

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../tests/walkthrough/scrut-setup.sh"
```
-->

```scrut
$ git splice diff -h | check-help preamble
NAME
    git-splice-diff - Show the changes push would send

SYNOPSIS
    git splice diff [--upstream <name>] [--stat] [path...]
```

## Description

```scrut
$ git splice diff -h | check-help section description
    Shows the file changes 'git splice push' would send to each splice's
    upstream, with paths as the upstream sees them. Purely local -- run
    'git splice fetch' first for up-to-date results.
```

In the [walkthrough's repositories](../01-getting-started/02-walkthrough.md), `vendor/pkg-a/` starts
one commit behind. Pull it first, so the example compares a local change
with an up-to-date upstream:

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

## Options

```scrut
$ git splice diff -h | check-help section options
    <path>...
        Shows only these splices, by their folders. Without paths, every
        splice.

    --upstream <name>
        Compares with this one of the upstreams the splice's .splice names,
        instead of its default upstream. A splice without the named
        upstream stops the command before it starts.
```

### `--stat`

```scrut
$ git splice diff -h | check-help option --stat
        Summarizes the changes per file instead, like 'git diff --stat'.
```

It summarizes the changes per file:

```scrut
$ git splice diff --stat
===  vendor/pkg-a
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

## No upstream branch

```scrut
$ git splice diff -h | check-help section no-upstream-branch
    For a splice whose upstream has no branch named like the current one, the
    diff is against upstream's default branch, from where the two meet, as a
    PR from the new branch would show it. Without a default branch upstream,
    the whole splice is new.
```

On a feature branch the upstream doesn't have, the diff is what a PR
into the upstream's default branch would show
([feature branches](../02-using-git-splice/README.md)).

<!-- Checks that every linked help section appears above, in order.
```scrut
$ git splice diff -h | check-help document "$TESTDIR/$TESTFILE"
```
-->
