# push

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice push -h
NAME
    git-splice-push - Publish local splice changes upstream

SYNOPSIS
    git splice push [--upstream <name>] [--force] (<path>... | --all)
    git splice push [--upstream <name>] [--force] --rebuilt-commit <commit> <path>

DESCRIPTION
    Publishes each splice's local changes: rebuilds the commits that changed
    it since its boundary, without its .splice file, and pushes them to its
    upstream URL. Nothing is written to the monorepo.

    Bottom-up: a splice below another is pushed first, since the push of the
    one above publishes its .splice, and a failed push stops the splices
    above it.

    If the upstream has no branch named like the current one, push creates it
    -- but only if it has commits upstream's default branch lacks, so working
    on a feature branch doesn't spawn empty branches upstream. Commits the
    feature branch got from the branch it was cut from count too: when
    upstream takes changes only through PRs, that's how they get there.

    On the monorepo's default branch, a default-pin names a tag or a commit,
    which isn't pushed to: push refuses there.

    --force overwrites the upstream branch with the monorepo's side: when the
    two share no history, or to discard commits only upstream has.

    --rebuilt-commit pushes <commit> instead of the rebuild, e.g. one whose
    history was edited after 'git splice rebuild <path>' printed it:
    messages reworded, commits squashed. Only the history: its files must be
    the folder's, and it must contain the synced commit -- with --force, it
    may also replace commits the upstream already has. Either way, a pull
    must be able to record it: a commit of the rebuild's history that isn't
    newer than the synced commit is refused. push checks only that; the
    rest of <commit>'s history -- its parents, the files of the commits
    before it -- is pushed as it is, as with 'git push'. Like every
    push, it records no sync point: the monorepo keeps rebuilding the
    original commits, and a later push publishes them too, unless 'git
    splice pull --bump <path>' records <commit> as the synced commit before
    the next change, as push reminds you.

    Only committed changes are pushed; push warns about uncommitted ones in a
    splice's folder.

    --upstream names one of the upstreams a splice's .splice names; without
    it, the splice's default upstream. A splice without the named upstream
    stops the command before it starts.
```

In the [walkthrough's repositories](README.md), `vendor/pkg-a/` starts
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

## An edited history: `--rebuilt-commit`

The next change names an internal ticket in its message, which shouldn't
go upstream:

```scrut
$ echo "a parser fix" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: fix INTERNAL-123"
```

[`rebuild`](rebuild.md) prints the commit `push` would send. Check it out
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
[edited-before-push](../scenarios/06-rewritten-history/01-edited-before-push/README.md).

## More

- On a feature branch, `push` creates the upstream branch of that name,
  but only for the splices that changed on it
  ([feature branches](feature-branches.md)).
- When the upstream moves to a new URL, `.splice` gets the new URL, and
  the next push sends the unpushed commits there
  ([upstream-moved](../scenarios/04-upstreams/04-upstream-moved/README.md)).
- Push before you move a splice with `git mv`: the push after the move
  squashes unpushed commits into it, a known bug
  ([moved-with-unpushed-commits](../scenarios/07-moved-folders/01-moved-with-unpushed-commits/README.md)).
- How the rebuild works: [design](../../docs/design/README.md#splicing-out-push-and-the-rebuild).
