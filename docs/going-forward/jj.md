# Jujutsu

[Jujutsu](https://github.com/jj-vcs/jj) (`jj`) is a version control
system that can share a repository with Git: in a *colocated* repository,
`.jj/` and `.git/` live side by side, and plain Git commands still work.
git splice doesn't work there yet
([#41](https://github.com/roschaefer/git-splice/issues/41)). This page
says what it needs, and what jj could do natively with what git splice
has learned.

## git splice in a colocated repository

jj keeps Git's `HEAD` detached, at the parent of the working-copy commit
(`@-`). Every git splice command that syncs with an upstream branch
stops there, since it follows the branch named like the current one:

```
$ git splice status
!!   not on a branch (detached HEAD) -- git splice requires a named branch
```

What has to be settled
([#41](https://github.com/roschaefer/git-splice/issues/41)):

- **Which upstream branch.** jj has no current branch, only bookmarks,
  which may or may not point at `@-`. An explicit branch, as a
  `--branch` per command or in `.splice`, would make the current branch
  only a default
  ([package managers](package-managers.md#explicit-branches)).
- **Which commit is `HEAD`.** The working-copy commit `@` holds the
  current changes, which Git sees as uncommitted.
- **Where `pull` and `clone` commit.** A commit on a detached `HEAD` is
  imported by jj's next command, and should then be an ordinary change.

## What a VCS could do natively

jj's developers would rather design nested repositories anew than port
Git's submodules or subtrees bug for bug
([jj#2919](https://github.com/jj-vcs/jj/issues/2919)). What git splice
found while building nested splices, each with an executable chapter:

- **Folders, not pointers.** A splice is ordinary files in the monorepo:
  every command works there as anywhere else, and a clone has them, with
  no setup. Only the sync with the upstream is special.
- **Three things to name.** Which copy it is: the
  [identity](../../test/concepts/splice-identity/README.md). Where it
  syncs: the [upstream](../../test/concepts/upstreams/README.md). And
  which version: the commit last synced, and the one a push would send
  ([sync model](../../test/concepts/sync-model/README.md)). Each answers
  a different question, and mixing them up caused bugs.
- **Metadata in the tree, not in commit messages.** `.splice` moves with
  its folder, and survives rebases and squash merges, since it names no
  monorepo commit. Where the splice's history starts is derived from the
  monorepo's history.
- **Containment has consequences.** A library reached by two paths is
  two copies, and a cycle is an endless tree
  ([nesting](../../test/concepts/nesting/README.md)).
- **Mirrors.** Nesting makes two copies of one splice unavoidable. A VCS
  that knows two paths are meant to be alike could report when they
  aren't, and could check both out as copy-on-write copies, sharing disk
  space without making them one folder ([mirrors](mirrors.md)).
- **History from the level above.** Once a nested repository's history
  is squashed into the one above it, the monorepo can't tell which of its
  changes were already published. The upstream above can
  ([spliced-elsewhere](../../test/scenarios/nested-splices/spliced-elsewhere.md)).
- **What a push publishes.** A remote for a subfolder is one mistyped
  command away from publishing the whole monorepo
  ([design](../design/accidental-monorepo-push.md)). And a monorepo
  commit that changes a splice and other folders reaches the upstream
  with its whole message. A policy that such commits touch nothing else,
  as asked for in jj#2919, isn't enforced by git splice.
