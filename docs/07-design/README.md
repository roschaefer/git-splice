# Design

`git-splice` keeps folders of a monorepo in sync with their own upstream
repositories, in both directions. Switching branches in the monorepo
switches the branch every folder syncs with.

## Principles

- **You can check it without reading it.** The state is plain Git: a committed
  `.splice`, refs under `refs/splices/`, and rebuilt commits that always come
  out the same. The docs write out the Git commands and run them against real
  output. And the tool only runs the `git` CLI, not a library, so
  [`GIT_TRACE` lists all it does](05-git-trace.md).
- **Let Git do the work.** Wherever Git can do a job, the tool calls Git: `git config` parses the state file,
  `cherry-pick` merges, `commit-tree` rebuilds, `log --left-right` compares.
  The tool's own code connects these, and stays small.
- **Changes cross the splice, commits don't.** The monorepo and each
  upstream keep separate histories. Upstream commits never become
  ancestors of the monorepo's commits, and the monorepo's merges and side
  branches never reach upstream.
- **The folder carries its own state.** A splice is a folder with a
  committed `.splice` file. Nothing about it lives in `.git/config`, so a
  clone of the monorepo has every splice, and `git mv` moves one.
- **Store as little as possible, derive the rest.** `.splice` holds the
  URL and the upstream commit the folder last matched, never a monorepo
  SHA. Where the last sync happened in the monorepo, and whether a push is
  needed, are worked out from history each time. Nothing a rebase or squash
  merge does can make them stale, and commands only inspect history since
  the last sync.
- **Deterministic rebuilds.** The same history always rebuilds into the
  same upstream commits, byte for byte. That makes status computable
  without storing anything about earlier pushes, and lets a second push
  fast-forward over the first.
- **Branches follow the monorepo.** On `feature-x`, every splice syncs with
  its upstream's `feature-x`. No branch is fixed per folder.
- **Name the target when writing, show everything when looking.** Commands
  that change the monorepo or an upstream need a path or `--all`.
  Commands that only look cover every splice.
- **Git's words keep Git's meaning.** `status`, `pull`, `upstream` or
  `rebase` do what they do in Git. A new word, like *splice*, is one Git
  doesn't use.
- **Refuse rather than guess.** With unrelated histories, or a path that
  can't be a ref name, the tool stops and says what to do.
- **Weigh every fix against its complexity.** An easy, safe fix goes in.
  A rare case gets documented, or an issue labelled
  [`edge case`](https://github.com/roschaefer/git-splice/issues?q=label%3A%22edge+case%22). An extreme one is ignored.

## The sync point

Like a subtree, a splice's files live directly in the monorepo. Like a
submodule, the monorepo records an upstream commit. But a gitlink says
which revision to check out; a splice's commit is a sync point, the
upstream revision the folder last matched. Later commits can change
the folder and leave the sync point where it is
([sync model](../03-concepts/02-sync-model.md)).

## Vocabulary

| Term | Meaning |
|---|---|
| **splice** | A folder of the monorepo that has its own upstream repository: "`vendor/a/` is spliced in from `github.com/x/a`", "the `vendor/a/` splice". Strictly, the noun means the joint, not the inserted piece ([why "splice"](06-name.md)). |
| **path** | Where the splice lives in the monorepo, e.g. `vendor/a/`. (`git subtree` calls it `--prefix`.) |
| **upstream** | The splice's own repository, named and given by URL in `.splice`, like a Git remote. |
| **state file** | `<path>/.splice`. Its presence in `HEAD` makes the folder a splice. |
| **synced commit**, **boundary**, **rebuild**, **upstream branch** | U(H), B, R and T of the [sync model](../03-concepts/02-sync-model.md). |
| **last sync** | The newest first-parent commit in the monorepo that changed `<path>/.splice`: the last pull, usually. Its `.splice` records U(H). |
| **mount** | Where a splice's history starts: its first `.splice`, or a `git mv`. |
| **key** | An upstream's short name in one repository, e.g. `lib`, mapped to its URL in the repository's config. Names its refs. |
| **splice in** | Bring upstream content into the monorepo: `clone`, `merge`, `pull`. |
| **splice out** | Publish the monorepo's changes upstream: `push`. |
| **sync state** | How R and T relate: `up to date`, `push`, `pull`, `diverged` and so on. |
| **default branch** | A repository's main branch (`HEAD` on the remote). The monorepo's default branch corresponds to upstream's. |
| **nested splice** | A splice below another one's folder ([nesting](../03-concepts/04-nesting.md)). |

"Default branch" belongs to a repository and is stored in `.splice` when
needed. It isn't called "fallback", which would describe only one of its
uses.

## Architecture

```
          monorepo                                  upstream (by URL)
 ┌────────────────────────────────┐
 │ HEAD                           │  fetch   ┌───────────────────────────┐
 │  └ vendor/a/                   │ <─────── │ refs/heads/*              │
 │      ├ .splice  (url, U(H))    │          └───────────────────────────┘
 │      └ …                       │                  ^
 │                                │                  │ push R
 │ refs/splices/<key>/heads/* (T) │                  │
 └────────────────────────────────┘                  │
        │ merge: cherry-pick of re-rooted trees      │
        │ push: rebuild of B..HEAD on top of U(B) ───┘
```

The state lives in two places, and both are plain Git data:

- **Committed:** `<path>/.splice`, with the upstream's URL and the synced
  commit U(H).
- **Local, rebuilt by `fetch`:** `refs/splices/<key>/heads/<branch>`, a copy of
  every upstream branch, under a key the repository's config maps the
  upstream's URL to.

Everything else, B, R and the sync state, is derived from those two and
the monorepo's history each time a command runs.
[Development](../10-contributing/01-development.md#code-map) maps this onto the code.

## State and upstreams

### The `.splice` file

The folder carries its upstream and synced commit in a committed `.splice`
file, so clones and branches have that state and `git mv` moves it.
[State and upstreams](01-state-and-upstreams.md#the-splice-file) explains the
file format, identity and default-branch choices; [Concepts](../03-concepts/README.md)
shows the file itself.

### Refs instead of remotes

Fetched upstream branches live in `refs/splices/<key>/heads/`, keyed by URL
rather than folder path. They can be shared by splices and worktrees without
creating Git remotes that could receive the whole monorepo by mistake.
[State and upstreams](01-state-and-upstreams.md#refs-instead-of-remotes)
explains the key mapping and ref layout.

The same chapter explains [branch mapping](01-state-and-upstreams.md#branches).

## How the commands work

Which splices a command acts on depends on what it does:

| Kind | Commands | Without a path |
|---|---|---|
| Starts a splice | `clone`, `init` | Take one URL and one path, no `--all`. `clone` defaults the path to the repository's name, as `git clone` does. |
| Splices in or out: changes the monorepo or an upstream | `merge`, `pull`, `push` | Refuses. Takes one or more paths, or `--all`. |
| Looks or prepares: changes neither | `status`, `diff`, `log`, `fetch` | Every splice; paths narrow it down. |

Splicing in writes a commit into the monorepo, and splicing out publishes
commits upstream. Both should name their target, as `git push <remote>`
does. An overview such as `status` is only useful if it's complete.

## Splicing in

`merge` turns already fetched upstream changes into **one ordinary
commit** in the monorepo, and never touches the network.
[Splicing in](02-splicing-in.md) explains starting a splice, re-rooting
upstream trees and merging with Git's normal conflict handling.

## Splicing out

A push sends the splice's history since the last sync, rebuilt as upstream
commits. [Splicing out](03-splicing-out.md) explains the rebuild, followed
by how `status`, `diff` and `log` use its result.

## Safety and limits

`git-splice` has no Git remotes for its upstreams.
[Safety and limits](04-safety-and-limits.md) explains why, the alternatives
considered, and the design's accepted limits.

## Checking what it runs

Everything `git-splice` does to a repository, it does by running the `git`
command line. [Checking what it runs](05-git-trace.md) shows how to inspect
those commands with `GIT_TRACE`, and what the trace doesn't show.

## Why the name "splice"

[Why the name "splice"](06-name.md) explains the rope, RNA and JavaScript
analogies behind the name.
