# push

`git splice push [--upstream <name>] [--base <branch>] [--force] (<path>… | --all)`  
`git splice push [--upstream <name>] [--base <branch>] [--force] --rebuilt-commit <commit> <path>`

Rebuilds the commits that changed each splice since the last sync,
without `.splice`, and pushes them to the upstream branch named like
yours. It writes nothing to the monorepo
([why](../concepts/sync-model/README.md#why-a-push-isnt-recorded)).

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice pull vendor/pkg-a >/dev/null
```

```scrut
$ echo "a local fix" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: a local fix"
```

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
$ git worktree add -q --detach ../edited "$(git splice rebuild vendor/pkg-a)" && git -C ../edited commit -q --amend -m "pkg-a: fix the parser"
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
[edited-before-push](../scenarios/up-to-date/push-ahead/edited-before-push/README.md).

## More

- On a feature branch, `push` creates the upstream branch of that name,
  but only for the splices that changed on it
  ([feature branches](feature-branches.md)).
- When the upstream moves to a new URL, `.splice` gets the new URL, and
  the next push sends the unpushed commits there
  ([upstream-moved](../scenarios/up-to-date/push-ahead/upstream-moved/README.md)).
- Push before you move a splice with `git mv`: the push after the move
  squashes unpushed commits into it, a known bug
  ([moved-with-unpushed-commits](../scenarios/up-to-date/push-ahead/moved-with-unpushed-commits/README.md)).
- How the rebuild works: [design](../../docs/design/README.md#splicing-out-push-and-the-rebuild).
