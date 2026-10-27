# log

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice log -h
NAME
    git-splice-log - Show commits push and pull would move

SYNOPSIS
    git splice log [--upstream <name>] [--graph] [path...]

DESCRIPTION
    Shows the commits between each splice and the upstream branch it syncs
    with, in both directions:

      <  a commit 'git splice push' would publish
      >  a commit 'git splice pull' would bring in
      =  the same change on both sides, e.g. cherry-picked upstream

    --graph draws both sides as a graph, like 'git log --graph', with the
    marks as its nodes, and the commit both sides build on as 'o'. The
    rebuild of the splice's commits is labeled (R), the upstream branch (T).

    If the upstream has no branch named like the current one, the other side
    is upstream's default branch, as for a PR from the branch push would
    create. If it lacks that one too, push would publish every commit.

    Each line shows the author, who is published along with the commit. Purely
    local -- run 'git splice fetch' first. Defaults to every splice when no
    paths are given.

    --upstream names one of the upstreams a splice's .splice names; without
    it, the splice's default upstream. A splice without the named upstream
    stops the command before it starts.
```
In the [walkthrough's repositories](README.md), the monorepo changes `vendor/pkg-a/`, and so
does its upstream:

```scrut
$ echo "a local fix" >>vendor/pkg-a/local.txt &&
>   git add vendor/pkg-a &&
>   git commit -qm "pkg-a: a local fix"
```

```scrut
$ git splice log
===  vendor/pkg-a (main)
< 9cdfdbb pkg-a: a local fix  (Walkthrough <walkthrough@example.com>)
> 703b936 pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
```

`--graph` draws both sides as a graph, down to the commit they build on,
`o`, and labels T, the fetched upstream branch, and R, the rebuild
`push` would send ([B, U(H), T and R](../concepts/sync-model/README.md)):

```scrut
$ git splice log --graph vendor/pkg-a
===  vendor/pkg-a (main)
< 9cdfdbb (R) pkg-a: a local fix  (Walkthrough <walkthrough@example.com>)
| > 703b936 (T) pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
|/  
o 9bb866a pkg-a: seed  (Walkthrough <walkthrough@example.com>)
```
