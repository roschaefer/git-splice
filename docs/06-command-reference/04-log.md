# log

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../tests/walkthrough/scrut-setup.sh"
```
-->

```scrut
$ git splice log -h | check-help preamble
NAME
    git-splice-log - Show commits push and pull would move

SYNOPSIS
    git splice log [--upstream <name>] [--graph] [path...]
```
## Description

```scrut
$ git splice log -h | check-help section description
    Shows the commits between each splice and the upstream branch it syncs
    with, in both directions. Purely local -- run 'git splice fetch' first.
```

In the [walkthrough's repositories](../01-getting-started/03-walkthrough.md), the monorepo changes `vendor/pkg-a/`, and so
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

## Options

```scrut
$ git splice log -h | check-help section options
    <path>...
        Shows only these splices, by their folders. Without paths, every
        splice.
```

### `--upstream`

```scrut
$ git splice log -h | check-help option --upstream
        Compares with this one of the upstreams the splice's .splice names,
        instead of its default upstream. A splice without the named
        upstream stops the command before it starts.
```

A splice with a fork and the original as upstreams can be compared with
either ([scenario](../09-scenarios/04-upstreams/02-several-upstreams/README.md)).

### `--graph`

```scrut
$ git splice log -h | check-help option --graph
        Draws both sides as a graph, like 'git log --graph', with the marks
        as its nodes, and the commit both sides build on as 'o'. The
        rebuild of the splice's commits is labeled (R), the upstream branch
        (T).
```

It draws both sides as a graph, down to the commit they build on,
`o`, and labels T, the fetched upstream branch, and R, the rebuild
`push` would send ([B, U(H), T and R](../03-concepts/03-sync-model/README.md)):

```scrut
$ git splice log --graph vendor/pkg-a
===  vendor/pkg-a (main)
< 9cdfdbb (R) pkg-a: a local fix  (Walkthrough <walkthrough@example.com>)
| > 703b936 (T) pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
|/  
o 9bb866a pkg-a: seed  (Walkthrough <walkthrough@example.com>)
```

## Output

```scrut
$ git splice log -h | check-help section output
    Each commit gets a mark:

      <  a commit 'git splice push' would publish
      >  a commit 'git splice pull' would bring in
      =  the same change on both sides, e.g. cherry-picked upstream

    Each line shows the author, who is published along with the commit.
```

`<` marks `9cdfdbb` above as a commit `push` would publish, `>` marks
`703b936` as one `pull` would bring in.

## No upstream branch

```scrut
$ git splice log -h | check-help section no-upstream-branch
    If the upstream has no branch named like the current one, the other side
    is upstream's default branch, as for a PR from the branch push would
    create. If it lacks that one too, push would publish every commit.
```

On a feature branch the upstream doesn't have, the other side is the
upstream's default branch, as for a PR
([feature branches](../02-using-git-splice/01-feature-branches.md)).

<!-- Checks that every linked help section appears above, in order.
```scrut
$ git splice log -h | check-help document "$TESTDIR/$TESTFILE"
```
-->
