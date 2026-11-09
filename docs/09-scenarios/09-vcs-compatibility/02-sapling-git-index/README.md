# Scenario: Sapling's Git index and branch state

Sapling works in a Git working copy, but `git-splice` observes Git's
index and branch state. In the pinned Sapling version, `sl amend` leaves
stale staged contents, and `sl prev` detaches Git's `HEAD`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds a monorepo with `vendor/lib/` as a splice:

```scrut
$ build_scenario scenario_sapling_git_index
```

<!--
```scrut
$ [[ "$(uname -s)" == Linux ]] || exit 80
```
-->

```scrut
$ sl --version 2>/dev/null | head -1
Sapling 0.2.20260929-102736+288e0c2d
```

A Sapling commit keeps Git on its branch:

```scrut
$ echo "fix" >>vendor/lib/src/parse.txt &&
>   sl commit -q -m "fix parse" &&
>   git status | head -n 1
On branch main
```

After an amend, Git reports staged and unstaged changes:

```scrut
$ echo "more" >>vendor/lib/src/parse.txt &&
>   sl amend -q &&
>   git status --short
MM vendor/lib/src/parse.txt
```

The push sends the amended commit, but warns about the stale index state:

```scrut
$ git splice push vendor/lib
??   vendor/lib: uncommitted changes aren't pushed -- commit them first
ok   vendor/lib: pushed df5904d to main
```

With no intentional staged changes in this example, reset the index:

```scrut
$ git reset -q && git status --short
```

Moving with Sapling detaches Git's `HEAD`, so syncing refuses:

```scrut
$ sl prev -q && git splice status
[5646f5] add vendor/lib
!!   not on a branch (detached HEAD) -- git splice requires a named branch
[1]
```

Select the Git branch again:

```scrut
$ git checkout -q main && git splice status
On branch main

  up to date  vendor/lib
```
