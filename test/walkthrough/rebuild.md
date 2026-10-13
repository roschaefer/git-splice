# rebuild

`git splice rebuild <path>`

Prints the commit `push` would send, R, without pushing it. It writes
nothing. The rebuild is deterministic, so a later push sees what was
pushed of it as already upstream.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice pull vendor/pkg-a >/dev/null && echo "a local fix" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: a local fix"
```

```scrut
$ git log --oneline "$(git splice rebuild vendor/pkg-a)"
2d02eb8 pkg-a: a local fix
703b936 pkg-a: a second commit, after the clone
9bb866a pkg-a: seed
```

With nothing changed since the last sync, it prints the synced commit
itself. It can also be checked out in a separate worktree, like a
[fetched upstream](fetch.md#looking-at-an-upstream).

## Editing it before the push

To reword or squash its commits before they go upstream, edit them in a
worktree and push the result with
[`push --rebuilt-commit`](push.md#an-edited-history---rebuilt-commit).
Like every `git splice push`, it finds the upstream's URL and branch
itself, updates the fetched upstream branch, and checks what it pushes:
the commit must have the folder's files and contain the synced commit.

## Pushing with plain Git

The rebuild is an ordinary commit, so plain Git can push it too, e.g. to
an upstream branch no monorepo branch is named like:

```scrut
$ git push -q https://git.example.com/pkg-a.git "$(git splice rebuild vendor/pkg-a)":refs/heads/release
```

```scrut
$ git -C "$WALKTHROUGH/upstream/pkg-a.git" log --oneline release
2d02eb8 pkg-a: a local fix
703b936 pkg-a: a second commit, after the clone
9bb866a pkg-a: seed
```

Then you pick the URL and the branch, nothing checks the commit, and the
monorepo learns about the push only with the next `fetch`: until then,
`status` still shows what was pushed as ahead. Prefer [`push`](push.md)
where it can do the job.
