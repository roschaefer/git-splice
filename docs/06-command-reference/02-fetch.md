# fetch

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../tests/walkthrough/scrut-setup.sh"
```
-->

```scrut
$ git splice fetch -h | check-help preamble
NAME
    git-splice-fetch - Fetch splice upstreams

SYNOPSIS
    git splice fetch [--upstream <name>] [--branch <name> --track | --no-track] [path...]
```
## Description

```scrut
$ git splice fetch -h | check-help section description
    Fetches every branch of each splice's upstreams, in parallel and each
    upstream once, and reports when the branch a splice syncs with has
    moved. Branches deleted upstream are pruned.
```

In the [walkthrough's repositories](../01-getting-started/02-walkthrough.md), someone pushes another
commit to `pkg-a`'s upstream:

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

## Options

```scrut
$ git splice fetch -h | check-help section options
    <path>...
        Fetches only the upstreams of these splices, by their folders.
        Without paths, every splice's.
```

### `--upstream`

```scrut
$ git splice fetch -h | check-help option --upstream
        Fetches only this one of the upstreams the splice's .splice names.
        Without it, a splice with several upstreams has each fetched.
```

A splice with a fork and the original as upstreams fetches both, unless
`--upstream` names one
([scenario](../09-scenarios/04-upstreams/02-several-upstreams/README.md)).

### Branch tracking

```scrut
$ git splice fetch -h | check-help option branch-tracking
    --branch <name> --track
        Also tracks that upstream branch on the current branch, without a
        pull or push: from then on, every command syncs the splice with it
        there, and 'git splice status' compares with it. See 'git splice
        merge --help'.

    --no-track
        Stops tracking one, so the splice syncs with the branch named like
        the current one again.
```

Tracking a branch only changes this clone's config, so it needs no pull
or push ([tracking another upstream branch
locally](../03-concepts/01-upstreams.md#tracking-another-upstream-branch-locally),
[scenario](../09-scenarios/03-branches-and-teamwork/07-tracked-branch/README.md)).

## Refs

```scrut
$ git splice fetch -h | check-help section refs
    The branches go to refs/splices/<key>/heads/*, where <key> is the
    upstream's key in this repository, e.g. lib for
    https://github.com/x/lib.git -- by URL, there is no Git remote; 'git
    splice key' prints and renames keys.
```

Fetched branches are ordinary Git refs under `refs/splices/<key>/heads/`
([URLs, keys and refs](../03-concepts/01-upstreams.md#urls-keys-and-refs)).

### Looking at an upstream

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
([refs instead of remotes](../07-design/02-state-and-upstreams.md#private-refs-avoid-an-accidental-push-target)).

<!-- Checks that every linked help section appears above, in order.
```scrut
$ git splice fetch -h | check-help document "$TESTDIR/$TESTFILE"
```
-->
