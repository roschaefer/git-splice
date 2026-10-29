# boundary

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice boundary -h
NAME
    git-splice-boundary - Print where a splice's rebuild starts

SYNOPSIS
    git splice boundary <path>

DESCRIPTION
    Prints the commit the rebuild of splice <path> starts from, B. The
    rebuild copies the commits after it on the current branch's
    first-parent history that change the folder's files:

      git log --first-parent "$(git splice boundary <path>)"..HEAD -- <path> ':!<path>/.splice'

    After a 'git mv' of the folder, the commits from before the move
    changed it under its old path. List those with the old path, up to the
    move's first parent, since another folder may take the old path later:

      git log --first-parent "$(git splice boundary <path>)"..<move>^ -- <old-path> ':!<old-path>/.splice'

    Usually B is the last pull, merge, clone or init. After a pull that
    merged commits that were never pushed, it's an earlier one, where the
    folder was the upstream commit .splice recorded.

    For a nested splice, run it in a worktree of a fetched commit of the
    upstream above, with the path there, to get where that upstream's
    rebuild of it starts:

      git worktree add --detach ../a refs/splices/a/heads/main
      git -C ../a splice boundary b

    Purely local, but the synced commit must have been fetched. Writes no
    ref and no monorepo commit.
```

In the [walkthrough's repositories](README.md), pull `vendor/pkg-a/`,
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

The folder's commits since then, on the first-parent history, are what
`push` rebuilds:

```scrut
$ git log --first-parent --oneline "$(git splice boundary vendor/pkg-a)"..HEAD -- vendor/pkg-a
2774c1a pkg-a: a local fix
```
