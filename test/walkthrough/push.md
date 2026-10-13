# push

`git splice push [--upstream <name>] [--base <branch>] [--force] (<path>… | --all)`

Rebuilds the commits that changed each splice since the last sync,
without `.splice`, and pushes them to the upstream branch named like
yours. It writes nothing to the monorepo.

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
