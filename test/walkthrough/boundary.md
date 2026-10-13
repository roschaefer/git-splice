# boundary

`git splice boundary <path>`

Prints the splice boundary, B: the monorepo commit where a splice last
synced, the newest commit on the first-parent history that changed its
`.splice`, e.g. the last `pull`. It answers "when was the library last
spliced in?" Like a boundary commit of `git log --boundary`, it starts
the range of the folder's commits since then.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice pull vendor/pkg-a >/dev/null && echo "a local fix" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: a local fix"
```

```scrut
$ git show -s --oneline "$(git splice boundary vendor/pkg-a)"
6ff5bf8 splice: pull vendor/pkg-a from main at 703b936
```

The folder's commits since then are what `push` rebuilds:

```scrut
$ git log --oneline "$(git splice boundary vendor/pkg-a)"..HEAD -- vendor/pkg-a
2774c1a pkg-a: a local fix
```

## Nested splices

A nested splice has two boundaries. In the monorepo, `boundary` prints
where the monorepo last synced it, often a pull of the splice above.
Where the upstream above last synced it is a commit of that upstream:
check out a fetched commit of it in a worktree, and run `boundary` there
with the path in that upstream, e.g. `b` for `vendor/a/b`:

    git worktree add --detach ../a refs/splices/a/main
    git -C ../a splice boundary b

See [nesting](../concepts/nesting/README.md).
