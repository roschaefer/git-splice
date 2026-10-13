# fetch

`git splice fetch [--upstream <name>] [path…]`

Fetches every branch of each splice's upstream, in parallel, into
`refs/splices/<key>/`, and calls out which branch moved. `status`,
`diff`, `log` and `merge` only use what was fetched last.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

Someone pushes to `pkg-a`'s upstream:

```scrut
$ simulate-remote-change vendor/pkg-a "pkg-a: add a feature"
ok   vendor/pkg-a: pushed a new commit upstream ('pkg-a: add a feature')
     git splice status         # to see it
     git splice pull vendor/pkg-a   # to bring it in
```

```scrut
$ git splice fetch
ok   vendor/pkg-a fetched (main moved 703b936..5099edf)
```

## Looking at an upstream

`fetch` keeps each upstream's complete history in the monorepo, under
`refs/splices/<key>/<branch>`, where the key is the upstream's short name
in this repository, from its URL: `https://git.example.com/pkg-a.git`
gets `pkg-a` ([`key`](key.md) renames it).
Every Git command reads it as `splices/<key>/<branch>`, so there's
nothing to clone:

```scrut
$ git log --oneline splices/pkg-a/main
5099edf pkg-a: add a feature
703b936 pkg-a: a second commit, after the clone
9bb866a pkg-a: seed
```

```scrut
$ git show splices/pkg-a/main:file.txt
pkg-a: seed
pkg-a: a second commit, after the clone
pkg-a: add a feature
```

For a checkout of the upstream, without a network round trip, add a
worktree, and remove it when you're done. Commits made there don't reach
upstream; changes belong in the monorepo, and `push` publishes them.

```scrut
$ git worktree add -q --detach ../pkg-a-upstream splices/pkg-a/main && ls ../pkg-a-upstream
file.txt
```

```scrut
$ git worktree remove ../pkg-a-upstream
```

`git log --all` shows the upstreams' histories too;
`git log --exclude='refs/splices/*' --all` leaves them out.

Upstreams are fetched and pushed by URL, with no Git remote, so a plain
`git push` can't send the whole monorepo to one by mistake
([more](../../docs/design/README.md#refs-instead-of-remotes)).
