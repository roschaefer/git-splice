# Jujutsu compared

[Jujutsu](https://github.com/jj-vcs/jj) (`jj`) is a version control
system that can share a repository with Git: in a *colocated* repository,
`.jj/` and `.git/` live side by side, and Git commands still work. jj has
no command of its own for a library in a folder: it
[doesn't support submodules](https://jj-vcs.github.io/jj/latest/git-compatibility/),
and the proposals for more aren't released ([below](#what-jj-plans)).

This page runs jj on the same library and monorepo as the other
comparisons, first with the library as a submodule, then as a splice. It
shows what works today, and where `git-splice` stops.
[What `git-splice` needs](../../../docs/going-forward/jj.md) to work there
is a page of its own.

The setup: `https://git.example.com/lib.git`, a library with 30 commits,
and a monorepo with an app. [How these pages run](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../scrut-setup.sh"
```
-->

<!-- jj's settings, and fixed dates and change ids, so commit hashes are
the same on every run. -->
<!--
```scrut
$ export JJ_CONFIG="$COMPARISON/jj.toml" JJ_TIMESTAMP=2026-01-01T00:00:00Z JJ_RANDOMNESS_SEED=1 TZ=UTC && printf '[user]\nname = "App Dev"\nemail = "app@example.com"\n[ui]\ncolor = "never"\npaginate = "never"\n' >"$JJ_CONFIG" && jj() { command jj "$@" 2>&1 | sed -E "s#$COMPARISON#\$COMPARISON#g"; return "${PIPESTATUS[0]}"; }
```
-->

```scrut
$ jj --version
jj 0.46.0-7d382314f9420b4b8d932245b49c99492c812b9f
```

## A submodule: jj doesn't look inside

```scrut
$ git submodule add -q https://git.example.com/lib.git vendor/lib &&
>   git commit -q -m "add lib as a submodule"
```

```scrut
$ jj git init --colocate
Done importing changes from the underlying Git repo.
ignoring git submodule at "vendor/lib"
Initialized repo in "."
```

You fix the library and use the fix in the app:

```scrut
$ echo "fix" >>vendor/lib/src/parse.txt && echo "call parse()" >>app/main.txt
```

jj sees the app's change only. The submodule stays at its commit, and the
change in it doesn't show, not even as a dirty submodule the way
[`git status`](../git-submodule.md#problem-1-the-monorepo-doesnt-see-the-librarys-files)
shows it:

```scrut
$ jj diff --stat
app/main.txt | 1 +
1 file changed, 1 insertion(+), 0 deletions(-)
```

## A splice: jj sees the files

A splice is files in a folder, plus `.splice`, so jj tracks them like any
other:

```scrut
$ cd ../splice-monorepo && git splice clone https://git.example.com/lib.git vendor/lib
===  vendor/lib: fetching https://git.example.com/lib.git
ok   vendor/lib: cloned bafd496 from main
```

```scrut
$ jj git init --colocate
Done importing changes from the underlying Git repo.
Setting the revset alias `trunk()` to `main@origin`.
Hint: The following remote bookmarks aren't associated with the existing local bookmarks:
  main@origin
Hint: Run the following command to keep local bookmarks updated on future pulls:
  jj bookmark track main@origin
Initialized repo in "."
```

```scrut
$ echo "fix" >>vendor/lib/src/parse.txt &&
>   echo "call parse()" >>app/main.txt &&
>   jj diff --stat
app/main.txt             | 1 +
vendor/lib/src/parse.txt | 1 +
2 files changed, 2 insertions(+), 0 deletions(-)
```

```scrut
$ jj commit -m "fix parse() and call it"
Working copy  (@) now at: qpvuntsm 9df2497b (empty) (no description set)
Parent commit (@-)      : sqpuoqvx eb9ac31c fix parse() and call it
```

## `git-splice` stops at the detached `HEAD`

jj keeps Git's `HEAD` detached, at the parent of the working-copy commit
(`@-`):

```scrut
$ git status | head -n 1
Not currently on any branch.
```

`git-splice` follows the upstream branch named like the current branch,
and here there is none:

```scrut
$ git splice push vendor/lib
!!   not on a branch (detached HEAD) -- git splice requires a named branch
[1]
```

## Back on a branch, by hand

jj's `main` bookmark is still at the clone, since a commit doesn't move a
bookmark. Moved to `@-`, and checked out with Git, it's a branch again:

```scrut
$ jj bookmark set main -r @-
Moved 1 bookmarks to sqpuoqvx eb9ac31c main* | fix parse() and call it
```

```scrut
$ git checkout -q main && git splice push vendor/lib
ok   vendor/lib: pushed 5069701 to main
```

That's the same commit a push from plain Git sends
([Sapling](sapling.md#fix-the-library-no-way-back)).

The library gets a release:

```scrut
$ git clone -q https://git.example.com/lib.git ../lib-dev &&
>   echo "1.3" >../lib-dev/VERSION &&
>   git -C ../lib-dev add VERSION &&
>   git -C ../lib-dev commit -q -m "release 1.3" &&
>   git -C ../lib-dev push -q
```

```scrut
$ git splice pull vendor/lib
ok   vendor/lib fetched (main moved 5069701..9a471d2)
ok   vendor/lib: pulled 9a471d2
```

jj imports the pull's commit at its next command, as it does with any
commit made with Git:

```scrut
$ jj log --no-graph -r '::@- ~ ::main@origin' -T 'description.first_line() ++ "\n"'
Reset the working copy parent to the new Git HEAD.
Done importing changes from the underlying Git repo.
splice: pull vendor/lib from main at 9a471d2
fix parse() and call it
splice: clone vendor/lib from main at bafd496
```

Git stays on `main` until jj moves the working copy, with `jj new` or
`jj commit`, so the bookmark and the checkout come before every sync:

```scrut
$ git status | head -n 1
On branch main
```

```scrut
$ jj new --quiet && git status | head -n 1
HEAD detached from eb9ac31
```

## What jj plans

None of these is released:

- **Submodules.** jj's design docs plan
  [submodule support](https://github.com/jj-vcs/jj/blob/main/docs/design/git-submodules.md),
  tracked in [#1405](https://github.com/jj-vcs/jj/issues/1405) and its
  sibling issues.
- **Composable histories.** An RFC for histories of several repositories
  in one, closed as a draft
  ([#10179](https://github.com/jj-vcs/jj/issues/10179)).
- **Views.** A filter that derives a folder's repository from the
  monorepo's history, keeping the upstream's commit hashes, like
  [Josh](../third-party/josh.md); closed unmerged
  ([#9889](https://github.com/jj-vcs/jj/pull/9889)).
- **`jj graft`.** A prototype discussed on jj's Discord: merges between a
  folder and another repository, with the commit they came from recorded
  in an extra commit header. That's Sapling's design
  ([Sapling](sapling.md#import-the-library)), and the
  [weak parent](../../../docs/going-forward/weak-parents.md) Git lacks.
