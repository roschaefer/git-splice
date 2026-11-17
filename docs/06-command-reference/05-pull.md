# pull

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../tests/walkthrough/scrut-setup.sh"
```
-->

```scrut
$ git splice pull -h | check-help preamble
NAME
    git-splice-pull - Fetch and splice in upstream changes

SYNOPSIS
    git splice pull [--upstream <name>] [--branch <name> [--track]] [--bump | --rebase] [--no-fork-point] [--message-template <template>] [--recursive] [--exec <command>] (<path>... | --all)
    git splice pull [<option>...] -m <message> <path>
```

## Description

```scrut
$ git splice pull -h | check-help section description
    'git splice fetch' followed by 'git splice merge': fetches the splices'
    upstreams in parallel, then splices their changes in, as one ordinary
    commit per splice.
```

In the [walkthrough's repositories](../01-getting-started/02-walkthrough.md), `vendor/pkg-a/` is
already one commit behind. Splice in `pkg-b/`, then push another commit
to its upstream, so both splices are behind:

```scrut
$ git splice clone https://git.example.com/pkg-b.git vendor/pkg-b >/dev/null &&
>   git clone -q "$WALKTHROUGH/upstream/pkg-b.git" ../pkg-b &&
>   echo "pkg-b: add a feature" >>../pkg-b/file.txt &&
>   git -C ../pkg-b commit -qam "pkg-b: add a feature" &&
>   git -C ../pkg-b push -q
```

Commands that change the monorepo or an upstream name their splices, or
take `--all`:

```scrut
$ git splice pull --all
ok   vendor/pkg-a fetched
ok   vendor/pkg-b fetched (main moved 9b3cb02..b937c4f)
ok   vendor/pkg-a: pulled 703b936
ok   vendor/pkg-b: pulled b937c4f
```

Each splice gets one commit. The monorepo's history stays linear:

```scrut
$ git log --oneline
6ed2f79 splice: pull vendor/pkg-b from main at b937c4f
dcf70b0 splice: pull vendor/pkg-a from main at 703b936
a73990e splice: clone vendor/pkg-b from main at 9b3cb02
d2867e9 lib-c: first version
3aef6fd splice: clone vendor/pkg-a from main at 9bb866a
ebe3b2b initial commit
```

## Options

```scrut
$ git splice pull -h | check-help section options
    <path>...
        The splices to pull, by their folders.

    --all
        Pulls every splice: each one the monorepo has, as with --recursive.

    --upstream <name>
        Pulls from this one of the upstreams the splice's .splice names,
        instead of its default upstream. A splice without the named
        upstream stops the command before it starts. The splices below,
        selected or not, are fetched from every upstream they name: names
        are only unique within one .splice, and any of them may have the
        synced commit the pull moves to.
```

### Merge options

```scrut
$ git splice pull -h | check-help option merge-options
    --branch <name>
        Pulls this upstream branch, for this pull only; see 'git splice
        merge --help'.

    --track
        With --branch, also tracks it on the current branch; see 'git splice
        merge --help'.

    --bump
        Also moves the synced commit up to the upstream branch when there's
        nothing to pull, e.g. right after a push; see 'git splice merge
        --help'.

    --rebase
        Rebases instead of merging, like 'git pull --rebase'; see 'git
        splice merge --help'.

    --no-fork-point
        Merges a rewritten upstream branch from Git's merge base, not from
        where the branch was before the rewrite; see 'git splice merge
        --help'.
```

They work as for [`merge`](04-merge.md#options), after the fetch.

### `-m`

```scrut
$ git splice pull -h | check-help option -m
        Gives the commit this message, for one splice; see 'git splice merge
        --help'.
```

It gives the commit your message instead, e.g. to say why you pull. It
takes one splice: each gets a commit of its own. `.splice` records the
upstream commit, so nothing needs to stay in the message:

```scrut
$ echo "pkg-b: fix the feature" >>../pkg-b/file.txt &&
>   git -C ../pkg-b commit -qam "pkg-b: fix the feature" &&
>   git -C ../pkg-b push -q
```

```scrut
$ git splice pull -m "take pkg-b's fix for the release" vendor/pkg-b
ok   vendor/pkg-b fetched (main moved b937c4f..e81697a)
ok   vendor/pkg-b: pulled e81697a
```

```scrut
$ git log -1 --format=%s
take pkg-b's fix for the release
```

### `--message-template`

```scrut
$ git splice pull -h | check-help option --message-template
        Gives each commit a message made from <template>, also with --all;
        see 'git splice merge --help'.
```

It works as for [`merge`](04-merge.md#--message-template), and unlike
`-m`, it takes `--all`:

```scrut
$ echo "pkg-b: speed up the feature" >>../pkg-b/file.txt &&
>   git -C ../pkg-b commit -qam "pkg-b: speed up the feature" &&
>   git -C ../pkg-b push -q
```

```scrut
$ git splice pull --all --message-template 'chore(deps): {command} {path} to {new}'
ok   vendor/pkg-a fetched
ok   vendor/pkg-b fetched (main moved e81697a..24c1958)
ok   vendor/pkg-a: nothing to pull
ok   vendor/pkg-b: pulled 24c1958
```

```scrut
$ git log -1 --format=%s
chore(deps): pull vendor/pkg-b to 24c1958
```

### `--recursive`

```scrut
$ git splice pull -h | check-help option --recursive
        Also pulls every splice below each one given, and any a pull above
        adds, and makes one commit of each given splice's pulls, with the
        message of its own pull. A conflict stops it: resolve it, commit,
        and run it again, which skips the splices already pulled. With
        --rebase, the pulls come first, on a detached HEAD at the last
        pull, and the branch's own commits since are rebased onto them
        once.
```

For [nested splices](../03-concepts/04-nesting.md): each splice is
pulled before the ones below it, which then start from what its
upstream recorded for them. A splice its upstream added is fetched and
pulled in the same run. A run stops at the first conflict, and the next
one goes on from there. When the last run ends, the monorepo gets one
commit per splice given: the message of that splice's own pull, from
`--message-template` if given, followed by the messages of the pulls
below it. Each splice's history has it on top of its own commits. `--all`
pulls each splice the monorepo has in the same way
([a recursive pull](../09-scenarios/05-nested-splices/05-recursion/01-recursive-pull/README.md)).

With `--rebase`, the pulls go at the newest commit that changed a
`.splice` in the tree, on a detached `HEAD`, so the branch stays where it
was until they're done. Then the branch's own commits since are rebased
onto their commit once. Rebasing onto each pull would replay the pulls
of the splices above it too
([rebased](../09-scenarios/05-nested-splices/05-recursion/01-recursive-pull/rebased.md)).

### `--exec`

```scrut
$ git splice pull -h | check-help option --exec
        Runs <command> through sh from the repository root at each execution
        checkpoint. GIT_SPLICE_EVENT names the checkpoint; GIT_SPLICE_PATH
        names its splice, and GIT_SPLICE_COMMIT its prepared or published
        commit, when applicable. Other values are empty. Zero continues;
        nonzero stops with completed work applied. Hooks must preserve the
        repository inputs required by continuation. stdin is closed; stdout
        and stderr are inherited.
```

The checkpoints are `after-fetch`, `after-merge`, and, for recursive pulls, `before-fold` and
`after-fold`. A hook runs synchronously; the next step starts
only after it succeeds. A failed hook ends this execution; completed changes
remain applied, and re-running `pull` goes on from there, as after a conflict.

Hooks can inspect tracked files and the index, but changing them or the
pull markers prevents continuation.

## Order

```scrut
$ git splice pull -h | check-help section order
    Also fetches the splices below each, and any its pull brings in:
    pulling a splice can move their synced commits. Top-down: a splice is
    pulled before the ones below it, and a failed fetch stops the splices
    above and below it.
```

`pull` also fetches the splices below the ones it pulls, and the ones
its pull brings in, since pulling the splice above can move their synced
commits ([nesting](../03-concepts/04-nesting.md)). It doesn't pull a
splice it brings in: `--recursive` does.

## Conflicts

```scrut
$ git splice pull -h | check-help section conflicts
    On a conflict, resolve it and run 'git commit' (or 'git cherry-pick
    --abort' to give up), then re-run pull for any splices left. With
    --rebase, it's 'git rebase --continue' (or 'git rebase --abort'); with
    --rebase --recursive, only for the branch's own commits, and 'git
    switch <branch>' gives up before.
```

When both sides changed the same lines, the pull stops at a conflict;
resolve it and `git commit` ([diverged history](../02-using-git-splice/01-diverged.md)).

Two developers who pull the same splice at different times get conflicts
in `.splice` when one merges the other's work. Pull the monorepo before
you pull a splice
([concurrent-pulls](../09-scenarios/03-branches-and-teamwork/04-concurrent-pulls/README.md)).

## Read more

```scrut
$ git splice pull -h | check-help section read-more

```

- A squash merge of the pull's branch keeps the sync point
  ([squash-merged-pull](../09-scenarios/03-branches-and-teamwork/03-squash-merged-pull/README.md)).
- When `git bisect` ends at a pull, the upstream commits squashed into
  it can be tested inside the monorepo, to find the one that broke it
  ([bisect-into-a-pull](../09-scenarios/03-branches-and-teamwork/05-bisect-into-a-pull/README.md)).

<!-- Checks that every linked help section appears above, in order.
```scrut
$ git splice pull -h | check-help document "$TESTDIR/$TESTFILE"
```
-->
