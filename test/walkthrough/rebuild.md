# rebuild

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice rebuild -h
NAME
    git-splice-rebuild - Print the commit push would send

SYNOPSIS
    git splice rebuild <path>

DESCRIPTION
    Prints the commit 'git splice push <path>' would send: the splice's
    history rebuilt without its .splice file, on top of the upstream commit
    it last synced with. If nothing changed since, that's the synced commit
    itself. The rebuild is deterministic, so a later push sees what was
    pushed of it as already upstream.

    Writes no ref and no monorepo commit. Purely local, but the synced
    commit must have been fetched.

    Push it to an upstream branch other than the one named like the current
    one, e.g. a release branch:

      git push <url> "$(git splice rebuild <path>)":refs/heads/<branch>

    or check it out in a separate worktree, since it has the upstream's
    layout, not the monorepo's:

      git worktree add ../rebuild "$(git splice rebuild <path>)"
```
```scrut
$ git splice pull vendor/pkg-a >/dev/null &&
>   echo "a local fix" >>vendor/pkg-a/file.txt &&
>   git commit -qam "pkg-a: a local fix"
```

```scrut
$ git log --oneline "$(git splice rebuild vendor/pkg-a)"
2d02eb8 pkg-a: a local fix
703b936 pkg-a: a second commit, after the clone
9bb866a pkg-a: seed
```

## Editing it before the push

To reword or squash its commits before they go upstream, edit them in a
worktree and push the result with
[`push --rebuilt-commit`](push.md#an-edited-history---rebuilt-commit).
Like every `git splice push`, it finds the upstream's URL and branch
itself, updates the fetched upstream branch, and checks what it pushes:
the commit must have the folder's files and contain the synced commit,
unless `--force` replaces published history.

## Pushing with plain Git

The rebuild is an ordinary commit, so plain Git can push it too, e.g. to
an upstream branch no monorepo branch is named like:

```scrut
$ rebuilt="$(git splice rebuild vendor/pkg-a)" &&
>   git push -q https://git.example.com/pkg-a.git "$rebuilt":refs/heads/release
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
