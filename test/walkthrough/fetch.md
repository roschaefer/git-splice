# fetch

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice fetch -h
NAME
    git-splice-fetch - Fetch splice upstreams

SYNOPSIS
    git splice fetch [--upstream <name>] [path...]

DESCRIPTION
    Fetches every branch of each splice's upstreams into
    refs/splices/<key>/heads/*, where <key> is the upstream's key in this
    repository, e.g. lib for https://github.com/x/lib.git -- by URL, there is
    no Git remote; 'git splice key' prints and renames keys. Branches deleted
    upstream are pruned. Defaults to every splice when no paths are given.
    Fetches upstreams in parallel, each once, and reports when the branch a
    splice syncs with moved.

    A splice whose .splice names several upstreams has each fetched, unless
    --upstream names one.
```
Someone pushes to `pkg-a`'s upstream:

```scrut
$ git clone -q "$WALKTHROUGH/upstream/pkg-a.git" ../pkg-a &&
>   echo "pkg-a: add a feature" >>../pkg-a/file.txt &&
>   git -C ../pkg-a commit -qam "pkg-a: add a feature" &&
>   git -C ../pkg-a push -q
```

```scrut
$ git splice fetch
ok   vendor/pkg-a fetched (main moved 703b936..5099edf)
```

## Looking at an upstream

Every Git command can read the fetched history, so there's nothing to
clone:

```scrut
$ git log --oneline splices/pkg-a/heads/main
5099edf pkg-a: add a feature
703b936 pkg-a: a second commit, after the clone
9bb866a pkg-a: seed
```

```scrut
$ git show splices/pkg-a/heads/main:file.txt
pkg-a: seed
pkg-a: a second commit, after the clone
pkg-a: add a feature
```

For a checkout of the upstream, without a network round trip, add a
worktree, and remove it when you're done. Commits made there don't reach
upstream; changes belong in the monorepo, and `push` publishes them.

```scrut
$ git worktree add -q --detach ../pkg-a-upstream splices/pkg-a/heads/main &&
>   ls ../pkg-a-upstream
file.txt
```

```scrut
$ git worktree remove ../pkg-a-upstream
```

`git log --all` shows the upstreams' histories too;
`git log --exclude='refs/splices/*' --all` leaves them out.

Upstreams are fetched and pushed by URL, with no Git remote, so a plain
`git push` can't send the whole monorepo to one by mistake
([refs instead of remotes](../../docs/design/README.md#refs-instead-of-remotes)).
