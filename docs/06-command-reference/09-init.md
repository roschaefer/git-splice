# init

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../tests/walkthrough/scrut-setup.sh"
```
-->

```scrut
$ git splice init -h | check-help preamble
NAME
    git-splice-init - Make an existing folder a splice of an empty repository

SYNOPSIS
    git splice init [-m <message>] <path> <url>
```
## Description

```scrut
$ git splice init -h | check-help section description
    Makes the existing folder <path> a splice, to be published to <url>: an
    empty repository you created for it. Commits <path>/.splice and nothing
    else. Your first 'git splice push <path>' then starts the upstream with
    that commit, the folder as it is now, followed by any commits after it.
    The folder's earlier history stays in the monorepo. If <url> has commits
    already, use 'git splice clone --merge <url> <path>'.

    Splices directly inside <path> follow its default branch from then on.
    Where that differs from the one they followed, init records theirs as
    default-branch in their .splice, in the same commit, so they keep
    syncing with it.
```

In the [walkthrough's repositories](../01-getting-started/03-walkthrough.md), `libs/c/` grew inside the monorepo, and
`lib-c.git` is empty:

```scrut
$ git splice init libs/c https://git.example.com/lib-c.git
ok   libs/c: initialized -- 'git splice push libs/c' publishes it
```

```scrut
$ git splice push libs/c
??   libs/c: upstream has no 'main' branch yet -- this push creates it
ok   libs/c: pushed 9dc1e6a to main
```

```scrut
$ git -C "$WALKTHROUGH/upstream/lib-c.git" log --format=%s main
splice: init libs/c
```

Why the folder's history before `init` stays in the monorepo:
[init-new-upstream](../09-scenarios/02-starting-a-splice/04-init-new-upstream/README.md).
In a fresh clone of the monorepo, commands treat the upstream as empty
until the first `fetch`, a known bug
([init-then-cloned](../09-scenarios/02-starting-a-splice/05-init-then-cloned/README.md)).

## Options

### `-m`

```scrut
$ git splice init -h | check-help option -m
        Gives the commit this message instead of the default one.
```

It works as for [`merge`](05-merge.md#-m).

<!-- Checks that every linked help section appears above, in order.
```scrut
$ git splice init -h | check-help document "$TESTDIR/$TESTFILE"
```
-->
