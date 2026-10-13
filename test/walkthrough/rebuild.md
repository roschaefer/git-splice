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

To push it to another upstream branch, e.g. a release branch:

```scrut
$ git push -q https://git.example.com/pkg-a.git "$(git splice rebuild vendor/pkg-a)":refs/heads/release
```

```scrut
$ git -C "$WALKTHROUGH/upstream/pkg-a.git" log --oneline release
2d02eb8 pkg-a: a local fix
703b936 pkg-a: a second commit, after the clone
9bb866a pkg-a: seed
```

With nothing changed since the last sync, it prints the synced commit
itself. It can also be checked out in a separate worktree, like a
[fetched upstream](fetch.md#looking-at-an-upstream).
