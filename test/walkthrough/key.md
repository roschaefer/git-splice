# key

`git splice key [--upstream <name>] <path> [<new-key>]`

Prints the key of a splice's upstream in this repository: its fetched
branches are `refs/splices/<key>/<branch>`. With `<new-key>`, renames
the key and moves its refs along.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice key vendor/pkg-a
pkg-a
```

```scrut
$ git splice key vendor/pkg-a a && git log --oneline -1 splices/a/main
ok   vendor/pkg-a: renamed key 'pkg-a' to 'a'
703b936 pkg-a: a second commit, after the clone
```

The first fetch records the key in the repository's config. How the
commands change these refs, and what they cost:
[splice-refs](../scenarios/04-upstreams/05-splice-refs/README.md). A splice with several
[upstreams](../concepts/upstreams/README.md) has a key for each, and
splices that name the same URL share one.
