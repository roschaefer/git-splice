# status

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git splice status -h
NAME
    git-splice-status - Show each splice's sync state

SYNOPSIS
    git splice status [--upstream <name>] [path...]

DESCRIPTION
    Shows the sync state of every splice. Purely local -- run 'git splice
    fetch' first for up-to-date results. Defaults to every splice when no
    paths are given.

    Every splice gets a line: the splices that need something come first,
    most urgent first -- "!!" and "??" mark problems -- and those that are up
    to date or unchanged come last.

    Like 'git status' against its upstream branch, it counts commits: "ahead"
    is how many 'git splice push' would publish, "behind" how many 'git
    splice pull' would bring in. 'git splice diff --stat' shows the files.

    For a splice whose upstream has no branch named like the current one,
    the comparison is with upstream's default branch, as for a PR: "new"
    counts the commits the push that creates the branch would publish, and
    how many the default branch has that this one lacks. "unchanged" means
    a PR from the branch would show no changes: the default branch has
    every commit, or the others change no files, e.g. a change and its
    revert.

    A splice that tracks an upstream branch on the current branch, by
    'git splice fetch --track' (or push, pull, merge), says so: "tracked on
    <branch>, local". It's in this repository's config only, so another
    clone of the monorepo shows the usual branch there.

    Like every command, status reads splices from the last commit. It warns
    about uncommitted changes in a splice's folder, which push leaves out.

    --upstream names one of the upstreams a splice's .splice names; without
    it, the splice's default upstream. A splice without the named upstream
    stops the command before it starts. A splice with several upstreams shows its
    upstream branch as <name>/<branch>.
```
In the [walkthrough's repositories](README.md), `vendor/pkg-a/`'s upstream has one commit the
monorepo doesn't have yet:

```scrut
$ git splice status
On branch main

  behind 1  vendor/pkg-a
```

## Sync states

`status` reports one of these states for each splice, and `merge`, `pull`
and `push` act on it. Each example is a small, tested scenario;
[all scenarios](../scenarios/README.md) cover more situations.
In the drawings, H is `HEAD`, R the rebuild `push` would send, and T
the fetched upstream branch; dashed commits are on no upstream branch
yet ([sync model](../concepts/sync-model/README.md)).

| `status` shows | Meaning | What to do |
| --- | --- | --- |
| `?? never fetched` | The upstream wasn't fetched in this clone yet. ([example](../scenarios/01-everyday-sync/04-never-fetched/README.md)) | Run `git splice fetch`. |
| `?? synced commit X isn't here` | `.splice` names an upstream commit this clone doesn't have, e.g. after `git pull` brought in a teammate's `git splice pull`. ([example](../scenarios/03-branches-and-teamwork/06-teammate-pulled/README.md)) | Run `git splice fetch`. If upstream doesn't have the commit any more, `pull` and `push` print the ways to pick a side. |
| `up to date` | Both sides are the same. ([example](../scenarios/01-everyday-sync/02-up-to-date/README.md))<br/>![T and R point at the same commit k](../scenarios/01-everyday-sync/02-up-to-date/up-to-date.drawio.svg) | Nothing to do. |
| `ahead N` | Only your side changed. ([example](../scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/README.md))<br/>![b changes the folder; its rebuild b prime, R, is on top of k, T](../scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/ahead.drawio.svg) | Run `git splice push`. |
| `behind N` | Only the upstream changed. ([example](../scenarios/01-everyday-sync/02-up-to-date/01-pull-ahead/README.md))<br/>![The upstream has l, T, on top of k, R](../scenarios/01-everyday-sync/02-up-to-date/01-pull-ahead/behind.drawio.svg) | Run `git splice pull`. |
| `ahead N, behind M` | Both sides changed since they last matched. ([example](../scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/03-diverged-common-ancestor/README.md))<br/>![l, T, and the rebuild b prime, R, both on top of k](../scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/03-diverged-common-ancestor/diverged.drawio.svg) | Run `git splice pull`, then `push`. On a conflict, resolve it and `git commit` first. |
| `!! unrelated history` | Both sides changed and share no history, e.g. the upstream was rebuilt from scratch. ([example](../scenarios/06-rewritten-history/03-diverged-unrelated-history/README.md))<br/>![The upstream has only z, T; the rebuild b prime, R, is on top of k, which no upstream branch has any more](../scenarios/06-rewritten-history/03-diverged-unrelated-history/unrelated-history.drawio.svg) | Pick a side. `merge`, `pull` and `push` refuse to guess and print the commands to keep either side, or both. |
| `unchanged, no upstream branch` or `new, ahead N` | The upstream has no branch with your branch's name. Compared with upstream's default branch, as for a PR: the PR would show no changes, or the default branch lacks N commits -- also ones from the branch yours was cut from. ([unchanged](../scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/README.md), [changed](../scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/01-feature-branch-changed/README.md), [from `main`](../scenarios/03-branches-and-teamwork/02-feature-branch-from-main/README.md), [stacked](../scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/01-feature-branch-changed/01-stacked-branch/README.md)) | Run `git splice push`. It creates the branch only if the PR would show changes. |

A splice that syncs with another branch than the one named like yours
names it, with `tracked on <branch>, local`
([example](../scenarios/03-branches-and-teamwork/07-tracked-branch/README.md)).

What `status` compares to tell the states apart: the
[sync model](../concepts/sync-model/README.md).
