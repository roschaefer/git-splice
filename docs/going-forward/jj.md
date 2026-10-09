# Jujutsu

[Jujutsu](https://github.com/jj-vcs/jj) (`jj`) is a version control
system that can share a repository with Git: in a *colocated* repository,
`.jj/` and `.git/` live side by side, and plain Git commands still work.
git splice doesn't work there yet
([#41](https://github.com/roschaefer/git-splice/issues/41)). This page
says what it needs.

## git splice in a colocated repository

jj keeps Git's `HEAD` detached, at the parent of the working-copy commit
(`@-`). Every git splice command that syncs with an upstream branch
stops there, since it follows the branch named like the current one:

```
$ git splice status
!!   not on a branch (detached HEAD) -- git splice requires a named branch
```

## Two branches

git splice reads two branches from Git, and maps each to a branch of the
upstream ([design](../design/README.md#branches)):

| In Git | Upstream branch | Also used for |
|---|---|---|
| **The current branch**, which `HEAD` names | The one with the same name | Which branch `status`, `pull` and `push` sync with |
| **The default branch**: `origin/HEAD`, else `init.defaultBranch` | The splice's `default-branch` if `.splice` records one, else the same name as the default branch of what it lives in | The base of a branch, unless `--base` names another |

jj has neither as Git has them. What could stand for each, and what's
open:

- **The current branch.** jj has bookmarks, but none is current: `@`
  isn't on one, and a commit doesn't move a bookmark, so the one at `@-`
  may be missing or lag behind. Candidates are the bookmark at `@-`, the
  nearest bookmark among `@`'s ancestors, or a branch named explicitly,
  per command or in `.splice`
  ([package managers](package-managers.md#explicit-branches)). Each has
  to refuse when it finds none, or more than one.
- **The default branch.** jj's `trunk()` revset names it: by default,
  the `main`, `master` or `trunk` bookmark of the remote. The bookmark's
  name would take the place of `origin/HEAD`.

What has to be settled
([#41](https://github.com/roschaefer/git-splice/issues/41)):

- **Which upstream branch**, from the two branches above.
- **Which commit is `HEAD`.** The working-copy commit `@` holds the
  current changes, which Git sees as uncommitted.
- **Where `pull` and `clone` commit.** A commit on a detached `HEAD` is
  imported by jj's next command, and should then be an ordinary change.
