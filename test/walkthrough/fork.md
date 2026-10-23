# Contributing through a fork

A library you don't maintain takes changes only as pull requests, and
may take its time with them. Meanwhile, the monorepo needs the changes
now. A fork of the library holds them in the meantime:

- **The fork's `main`** mirrors the original's `main`, and nothing else.
- **One branch per change**, on top of the fork's `main`. Each becomes a
  pull request to the original, on its own, so it can be reviewed and
  taken on its own. A pull request against the fork's own `main` shows
  what's still to send, and runs the library's CI.
- **`patches`** stacks all of them on the fork's `main`. The monorepo's
  `main` follows it: the splice gets every change, including those the
  original hasn't taken yet.

When the original moves on, the fork's `main` catches up, and the
branches are rebased onto it. A change the original took drops out of
`patches` in that rebase.

This repository splices [scrut](https://github.com/facebookincubator/scrut),
its test runner, this way:

| | in this walkthrough | for `scrut/` |
| --- | --- | --- |
| The original | `pkg-a` | [facebookincubator/scrut](https://github.com/facebookincubator/scrut) |
| The fork | `pkg-a-fork` | [roschaefer/scrut](https://github.com/roschaefer/scrut) |
| One branch per change | `fix/parser` | `docs/working-directory-grammar`, `fix/subprocess-full-timeouts`, `feat/test-jobs` |
| All changes | `patches` | `feat/scrut-parallel-jobs` ([roschaefer/scrut#1](https://github.com/roschaefer/scrut/pull/1)) |

[`scrut/.splice`](../../scrut/.splice) configures the fork as below
([#225](https://github.com/roschaefer/git-splice/pull/225)).
Meta doesn't merge scrut's pull requests on GitHub. It imports them,
and they come back as new commits
([export tools](../comparisons/third-party/export-tools.md#metas-shipit)).
This walkthrough's maintainer does the same.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

First, bring `pkg-a` up to date, as in the
[main walkthrough](README.md#pull):

```scrut
$ git splice pull vendor/pkg-a >/dev/null
```

## Fork the library

A host's "Fork" button copies the repository. Here, a bare clone next to
the original does:

```scrut
$ git clone -q --bare "$WALKTHROUGH/upstream/pkg-a.git" "$WALKTHROUGH/upstream/pkg-a-fork.git"
```

The splice gets the fork as a second upstream, and uses it by default.
Its `default-branch` makes the monorepo's `main` follow `patches`
instead of the fork's `main`
([upstreams](../concepts/upstreams/README.md)):

```scrut
$ git config --file vendor/pkg-a/.splice upstream.fork.url https://git.example.com/pkg-a-fork.git &&
>   git config --file vendor/pkg-a/.splice upstream.fork.default-branch patches &&
>   git config --file vendor/pkg-a/.splice splice.default-upstream fork &&
>   git commit -q -m "pkg-a: follow the fork's patches" -- vendor/pkg-a/.splice
```

```scrut
$ git config --file vendor/pkg-a/.splice --list | grep -v '^splice\.id='
splice.commit=703b9360f7ac335a1134e9b5771a90a7c09ba39a
splice.default-upstream=fork
upstream.origin.url=https://git.example.com/pkg-a.git
upstream.fork.url=https://git.example.com/pkg-a-fork.git
upstream.fork.default-branch=patches
```

## A change in the monorepo

The monorepo fixes the library where it uses it:

```scrut
$ echo "a parser fix" >>vendor/pkg-a/file.txt &&
>   git commit -qam "pkg-a: fix the parser"
```

The fork has no `patches` yet, so the first push creates it:

```scrut
$ git splice push vendor/pkg-a
??   vendor/pkg-a: upstream has no 'fork/patches' branch yet -- this push creates it
ok   vendor/pkg-a: pushed 7edd872 to fork/patches
```

## One branch per change

The pull request to the original gets a branch of its own, with only
this change on the fork's `main`. In a clone of the fork, with the
original as a second remote:

```scrut
$ git clone -q "$WALKTHROUGH/upstream/pkg-a-fork.git" "$WALKTHROUGH/pkg-a-fork" &&
>   cd "$WALKTHROUGH/pkg-a-fork" &&
>   git remote add original "$WALKTHROUGH/upstream/pkg-a.git"
```

```scrut
$ git switch -q -c fix/parser origin/main &&
>   git cherry-pick origin/patches
[fix/parser 7edd872] pkg-a: fix the parser
 Date: Thu Jan 1 00:00:00 2026 +0000
 1 file changed, 1 insertion(+)
```

```scrut
$ git push -q origin fix/parser
```

```scrut
$ git log --format=%s origin/main..fix/parser
pkg-a: fix the parser
```

From `fix/parser`, open a pull request against the fork's `main` to run
the library's CI, and one against the original. A change that needs
another one, like `--jobs` needs the `subprocess` upgrade in scrut,
carries that one's commit too, and its pull request waits for the
other's.

## The original moves on

The original's maintainer commits something else:

```scrut
$ git clone -q "$WALKTHROUGH/upstream/pkg-a.git" "$WALKTHROUGH/pkg-a" &&
>   cd "$WALKTHROUGH/pkg-a" &&
>   git config user.name "Maintainer" &&
>   git config user.email "maintainer@example.com"
```

```scrut
$ echo "a new feature" >feature.txt &&
>   git add feature.txt &&
>   git commit -q -m "add a feature" &&
>   git push -q origin main
```

The fork's `main` catches up. It never has commits of its own, so that's
a fast-forward:

```scrut
$ cd "$WALKTHROUGH/pkg-a-fork" &&
>   git fetch -q original &&
>   git push -q origin original/main:main
```

Then the branches are rebased onto it and force-pushed, each with a
lease on where it was:

```scrut
$ git fetch -q origin &&
>   git rebase -q origin/main fix/parser &&
>   git switch -q -c patches origin/patches &&
>   git rebase -q origin/main &&
>   git push -q --force-with-lease origin fix/parser patches
```

```scrut
$ git log --format=%s origin/patches
pkg-a: fix the parser
add a feature
pkg-a: a second commit, after the clone
pkg-a: seed
```

The monorepo pulls the rebased `patches`. The commit it synced last is
still in its history, so this is an ordinary pull:

```scrut
$ cd "$WALKTHROUGH/monorepo" && git splice pull vendor/pkg-a
ok   vendor/pkg-a fetched from fork (patches moved 7edd872..e645616)
ok   vendor/pkg-a: pulled e645616
```

```scrut
$ git splice status
On branch main

  up to date  vendor/pkg-a -> fork/patches
```

## The original takes the change

The maintainer takes the pull request as a new commit on `main`, the way
Meta's import does: same change, new message, new parent.

```scrut
$ cd "$WALKTHROUGH/pkg-a" &&
>   git fetch -q "$WALKTHROUGH/upstream/pkg-a-fork.git" fix/parser &&
>   git cherry-pick --no-commit FETCH_HEAD &&
>   git commit -q -m "Fix the parser (#1)" &&
>   git push -q origin main
```

The fork catches up again. This time, the rebase finds the change already
on `main` and drops it from `patches`, which becomes the fork's `main`:

```scrut
$ cd "$WALKTHROUGH/pkg-a-fork" &&
>   git fetch -q original &&
>   git push -q origin original/main:main &&
>   git fetch -q origin &&
>   git -c advice.skippedCherryPicks=false rebase -q origin/main patches &&
>   git push -q --force-with-lease origin patches :fix/parser
```

```scrut
$ git log --format=%s origin/patches
Fix the parser (#1)
add a feature
pkg-a: a second commit, after the clone
pkg-a: seed
```

The rebase rewrote the monorepo's last synced commit, the fix on top of
`add a feature`, away. But the folder already has the files of the new
`patches`, so the pull only records it:

```scrut
$ cd "$WALKTHROUGH/monorepo" && git splice pull vendor/pkg-a
ok   vendor/pkg-a fetched from fork (patches moved e645616..35d9f8f)
ok   vendor/pkg-a: recorded 35d9f8f as the synced commit -- the folder already has its files
```

```scrut
$ git splice status
On branch main

  up to date  vendor/pkg-a -> fork/patches
```

```scrut
$ cat vendor/pkg-a/file.txt
pkg-a: seed
pkg-a: a second commit, after the clone
a parser fix
```

If the maintainer edited the change on the way, as Meta's reviewers
sometimes do, the rebase conflicts in the fork instead. Resolve it with
the original's version, and the monorepo pulls that.

## Push before the fork rebases

Push the monorepo's changes to `patches` before the fork rebases it, so
the rebased `patches` has them. Then a pull only ever brings in the
fork's version of what the monorepo already has, even where the rebase
rewrote the synced commit away: like `git pull --rebase`, `pull` merges
from where `patches` was before, its fork point in the fetched branch's
reflog ([patch-branch-rebased](../scenarios/06-rewritten-history/04-patch-branch-rebased/README.md)).
A change that wasn't pushed in time needs
[`pull --rebase`](../scenarios/06-rewritten-history/04-patch-branch-rebased/01-unpushed-local-commit/README.md).
