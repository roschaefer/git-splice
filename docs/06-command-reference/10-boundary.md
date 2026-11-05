# boundary

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../tests/walkthrough/scrut-setup.sh"
```
-->

```scrut
$ git splice boundary -h | check-help preamble
NAME
    git-splice-boundary - Print where a splice's rebuild starts

SYNOPSIS
    git splice boundary <path>
```

## Description

```scrut
$ git splice boundary -h | check-help section description
    Prints the commit the rebuild of splice <path> starts from, B. Usually
    B is the last pull, merge, clone or init. After a pull that merged
    commits that were never pushed, it's an earlier one, where the folder
    was the upstream commit .splice recorded. Purely local, but the synced
    commit must have been fetched. Writes no ref and no monorepo commit.
```

In the [walkthrough's repositories](../01-getting-started/03-walkthrough.md), pull `vendor/pkg-a/`,
then add a local commit. Its boundary is the pull commit:

```scrut
$ git splice pull vendor/pkg-a >/dev/null &&
>   echo "a local fix" >>vendor/pkg-a/file.txt &&
>   git commit -qam "pkg-a: a local fix"
```

`boundary` prints that pull:

```scrut
$ git show -s --oneline "$(git splice boundary vendor/pkg-a)"
6ff5bf8 splice: pull vendor/pkg-a from main at 703b936
```

## The rebuilt commits

```scrut
$ git splice boundary -h | check-help section the-rebuilt-commits
    The rebuild copies the commits after B on the current branch's
    first-parent history that change the folder's files:

      git log --first-parent "$(git splice boundary <path>)"..HEAD -- <path> ':!<path>/.splice'

    After a 'git mv' of the folder, the commits from before the move
    changed it under its old path. List those with the old path, up to the
    move's first parent, since another folder may take the old path later:

      git log --first-parent "$(git splice boundary <path>)"..<move>^ -- <old-path> ':!<old-path>/.splice'

    B itself is copied too where the rebuild starts at the commit that made
    the folder a splice, or where B's folder isn't the upstream commit .splice
    records and nothing unpushed came before it: then list from B's parent.
```

The folder's commits since then, on the first-parent history, are what
`push` rebuilds:

```scrut
$ git log --first-parent --oneline "$(git splice boundary vendor/pkg-a)"..HEAD -- vendor/pkg-a
2774c1a pkg-a: a local fix
```

## Nested splices

```scrut
$ git splice boundary -h | check-help section nested-splices
    For a nested splice, run it in a worktree of a fetched commit of the
    upstream above, with the path there, to get where that upstream's
    rebuild of it starts:

      git worktree add --detach ../a refs/splices/a/heads/main
      git -C ../a splice boundary b
```

A nested splice's history from before the last sync of the splice above
comes from that upstream
([nesting](../03-concepts/05-nesting/README.md)), so ask there where its
rebuild starts.

<!-- Checks that every linked help section appears above, in order.
```scrut
$ git splice boundary -h | check-help document "$TESTDIR/$TESTFILE"
```
-->
