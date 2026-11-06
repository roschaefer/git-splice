# key

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../tests/walkthrough/scrut-setup.sh"
```
-->

```scrut
$ git splice key -h | check-help preamble
NAME
    git-splice-key - Print or rename an upstream's key

SYNOPSIS
    git splice key [--upstream <name>] <path> [<new-key>]
```

## Description

```scrut
$ git splice key -h | check-help section description
    Prints the key splice <path>'s upstream has in this repository: its
    fetched branches are refs/splices/<key>/heads/<branch>, e.g. for
    'git log splices/<key>/heads/main'.
```

In the [walkthrough's repositories](../01-getting-started/02-walkthrough.md), `vendor/pkg-a/` has
already been fetched, so its upstream has the key `pkg-a`:

```scrut
$ git splice key vendor/pkg-a
pkg-a
```

## Options

```scrut
$ git splice key -h | check-help section options
    --upstream <name>
        Names the upstream, as <path>/.splice does in [upstream "<name>"].
        Without it, the splice's default upstream.
```

### `<new-key>`

```scrut
$ git splice key -h | check-help option new-key
        Renames the key and moves its refs along. Renaming it also renames
        it in the tracked upstream branches, branch.<branch>.splice =
        <key>:<name>.
```

Rename it to `a`:

```scrut
$ git splice key vendor/pkg-a a
ok   vendor/pkg-a: renamed key 'pkg-a' to 'a'
```

The fetched branch moves with it:

```scrut
$ git log --oneline -1 splices/a/heads/main
703b936 pkg-a: a second commit, after the clone
```

## Keys

```scrut
$ git splice key -h | check-help section keys
    A key belongs to an upstream URL, so splices with the same URL share it.
    The first fetch of an upstream records its key in the repository's
    config, as splice.<key>.url, from the end of its URL: lib for
    https://github.com/x/lib.git, or x-lib, then github.com-x-lib, if that's
    taken. A key is lower-case letters, digits, ".", "_" and "-", at most 64
    long.
```

A key belongs to an upstream URL, so every splice of that URL shares it
([URLs, keys and refs](../03-concepts/01-upstreams.md#urls-keys-and-refs),
[choosing a key](../03-concepts/01-upstreams.md#choosing-a-key)).
How the commands change these refs, and what they cost:
[splice refs](../09-scenarios/04-upstreams/05-splice-refs/README.md).

<!-- Checks that every linked help section appears above, in order.
```scrut
$ git splice key -h | check-help document "$TESTDIR/$TESTFILE"
```
-->
