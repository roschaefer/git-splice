# push

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../tests/walkthrough/scrut-setup.sh"
```
-->

```scrut
$ git splice push -h | check-help preamble
NAME
    git-splice-push - Publish local splice changes upstream

SYNOPSIS
    git splice push [--upstream <name>] [--branch <name> [--track]] [--force] (<path>... | --all)
    git splice push [--upstream <name>] [--branch <name>] [--force] --rebuilt-commit <commit> <path>
```

## Description

```scrut
$ git splice push -h | check-help section description
    Publishes each splice's local changes: rebuilds the commits that changed
    it since its boundary, without its .splice file, and pushes them to its
    upstream URL. Nothing is written to the monorepo. Only committed changes
    are pushed; push warns about uncommitted ones in a splice's folder.
```

In the [walkthrough's repositories](../01-getting-started/02-walkthrough.md), `vendor/pkg-a/` starts
one commit behind. Pull it to start from an up-to-date splice:

```scrut
$ git splice pull vendor/pkg-a >/dev/null
```

Then commit a local change:

```scrut
$ echo "a local fix" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: a local fix"
```

Push it upstream:

```scrut
$ git splice push vendor/pkg-a
ok   vendor/pkg-a: pushed 2d02eb8 to main
```

The upstream got the commit, with the monorepo commit's message and
author:

```scrut
$ git -C "$WALKTHROUGH/upstream/pkg-a.git" log --format=%s main
pkg-a: a local fix
pkg-a: a second commit, after the clone
pkg-a: seed
```

`push` updates the fetched upstream branch too, so the splice is up to
date. Its `.splice` still names the commit from before the push; a later
push rebuilds from there and sees what was already pushed:

```scrut
$ git splice status
On branch main

  up to date  vendor/pkg-a
```

## Options

```scrut
$ git splice push -h | check-help section options
    <path>...
        The splices to push, by their folders.

    --all
        Pushes every splice.

    --upstream <name>
        Pushes to this one of the upstreams the splice's .splice names,
        instead of its default upstream. A splice without the named
        upstream stops the command before it starts.
```

### Branch tracking

```scrut
$ git splice push -h | check-help option branch-tracking
    --branch <name>
        Pushes to this upstream branch, for this push only, as 'git splice
        pull --branch' pulls from one: with the same checks, and created
        like the one named like the current branch. It doesn't change
        .splice, and the splices below keep theirs.

    --track
        With --branch, also tracks it on the current branch, like 'git push
        -u'; see 'git splice merge --help'.
```

They work as for [`merge`](04-merge.md#branch-tracking): the push goes
to that upstream branch instead.

### `--force`

```scrut
$ git splice push -h | check-help option --force
        Overwrites the upstream branch with the monorepo's side: when the
        two share no history, or to discard commits only upstream has.
```

When the upstream was rebuilt from scratch, and the two sides share no
history, `push` refuses and prints the ways to pick a side; `--force`
keeps the monorepo's
([unrelated-history](../09-scenarios/06-rewritten-history/03-diverged-unrelated-history/README.md)).

### `--rebuilt-commit`

```scrut
$ git splice push -h | check-help option --rebuilt-commit
        Pushes <commit> instead of the rebuild, e.g. one whose history was
        edited after 'git splice rebuild <path>' printed it: messages
        reworded, commits squashed. Only the history: its files must be the
        folder's, and it must contain the synced commit -- with --force, it
        may also replace commits the upstream already has. Either way, a
        pull must be able to record it: a commit of the rebuild's history
        that isn't newer than the synced commit is refused. push checks only
        that; the rest of <commit>'s history -- its parents, the files of
        the commits before it -- is pushed as it is, as with 'git push'.

        Like every push, it records no sync point: the monorepo keeps
        rebuilding the original commits, and a later push publishes them
        too, unless 'git splice pull --bump <path>' records <commit> as the
        synced commit before the next change, as push reminds you.
```

The next change names an internal ticket in its message, which shouldn't
go upstream:

```scrut
$ echo "a parser fix" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: fix INTERNAL-123"
```

[`rebuild`](10-rebuild.md) prints the commit `push` would send. Check it out
in a worktree of its own, since it has the upstream's layout, and reword
it there:

```scrut
$ git worktree add -q --detach ../edited "$(git splice rebuild vendor/pkg-a)" &&
>   git -C ../edited commit -q --amend -m "pkg-a: fix the parser"
```

`--rebuilt-commit` pushes the edited commit instead of the rebuild. It
refuses a commit whose files differ from the folder's, or that doesn't
contain the synced commit -- unless `--force` is given too, to edit
commits the upstream already has. The rest of its history goes upstream
as it is, as with `git push`:

```scrut
$ git splice push --rebuilt-commit "$(git -C ../edited rev-parse HEAD)" vendor/pkg-a
ok   vendor/pkg-a: pushed f3dbe32 to main
??   vendor/pkg-a: run 'git splice pull --bump vendor/pkg-a' before the next change to it -- that records f3dbe32 as the synced commit
```

```scrut
$ git -C "$WALKTHROUGH/upstream/pkg-a.git" log -1 --format=%s main
pkg-a: fix the parser
```

Like every push, it records no sync point, and the monorepo still has
the original commit. Pull with `--bump` before the next change to the
splice, as `push` reminds you: the folder has the pushed commit's files,
so the pull records it as the synced commit, and later pushes build on
it:

```scrut
$ git splice pull --bump vendor/pkg-a
ok   vendor/pkg-a fetched
ok   vendor/pkg-a: recorded f3dbe32 as the synced commit -- the folder already has its files
```

```scrut
$ git worktree remove ../edited
```

Why pull right away, and what `push` checks:
[edited-before-push](../09-scenarios/06-rewritten-history/01-edited-before-push/README.md).

The other way round, [`merge --rebuilt-commit`](04-merge.md#--rebuilt-commit)
brings work committed in such a worktree into the monorepo.

## Upstream branch

```scrut
$ git splice push -h | check-help section upstream-branch
    If the upstream has no branch named like the current one, push creates
    it -- but only if a PR from it to upstream's default branch would show
    changes, so working on a feature branch doesn't spawn empty branches
    upstream. Changes the feature branch got from the branch it was cut
    from count too: when upstream takes changes only through PRs, that's
    how they get there.

    On the monorepo's default branch, a default-pin names a tag or a commit,
    which isn't pushed to: push refuses there.
```

On a feature branch, `push` creates the upstream branch of that name,
but only for the splices that changed on it
([feature branches](../02-using-git-splice/README.md)).

## Order

```scrut
$ git splice push -h | check-help section order
    Bottom-up: a splice below another is pushed first, since the rebuild of
    the one above records it at the commit its push sends, and a failed
    push stops the splices above it.
```

Pushing the splice above sends the `.splice` of the one below as the
rebuild wrote it, recording the rebuild of the one below: what its
upstream gets with the same push.
So one `push --all` leaves every upstream recording what the one inside
it got from the monorepo, without `pull --bump` in between. An upstream
that moved on since is pulled first, as before any push
([nesting](../03-concepts/04-nesting.md)).

## Read more

```scrut
$ git splice push -h | check-help section read-more

```

- When the upstream moves to a new URL, `.splice` gets the new URL, and
  the next push sends the unpushed commits there
  ([upstream-moved](../09-scenarios/04-upstreams/04-upstream-moved/README.md)).
- A splice moved with `git mv` keeps its unpushed commits: the push
  after the move sends them as they were
  ([moved-with-unpushed-commits](../09-scenarios/07-moved-folders/01-moved-with-unpushed-commits/README.md)).
- Why the rebuild is deterministic: [design](../07-design/README.md#principles).

<!-- Checks that every linked help section appears above, in order.
```scrut
$ git splice push -h | check-help document "$TESTDIR/$TESTFILE"
```
-->
