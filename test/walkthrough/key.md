# key

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice key -h
NAME
    git-splice-key - Print or rename an upstream's key

SYNOPSIS
    git splice key [--upstream <name>] <path> [<new-key>]

DESCRIPTION
    Prints the key splice <path>'s upstream has in this repository: its
    fetched branches are refs/splices/<key>/heads/<branch>, e.g. for
    'git log splices/<key>/heads/main'. With <new-key>, renames the key and
    moves its refs along.

    --upstream names the upstream, as <path>/.splice does in
    [upstream "<name>"]. Without it, the splice's default upstream.

    A key belongs to an upstream URL, so splices with the same URL share it.
    The first fetch of an upstream records its key in the repository's config,
    as splice.<key>.url, from the end of its URL: lib for
    https://github.com/x/lib.git, or x-lib, then github.com-x-lib, if that's
    taken. A key is lower-case letters, digits, ".", "_" and "-", at most 64
    long.
```
```scrut
$ git splice key vendor/pkg-a
pkg-a
```

```scrut
$ git splice key vendor/pkg-a a
ok   vendor/pkg-a: renamed key 'pkg-a' to 'a'
```

```scrut
$ git log --oneline -1 splices/a/heads/main
703b936 pkg-a: a second commit, after the clone
```

How the commands change these refs, and what they cost:
[splice refs](../scenarios/04-upstreams/05-splice-refs/README.md).
