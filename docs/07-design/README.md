# Design

`git-splice` keeps folders of a monorepo in sync with their own upstream
repositories. The files are ordinary files; the histories stay separate.
This chapter explains the choices behind the [sync model](../03-concepts/02-sync-model.md).

## Principles

- **Changes cross the splice, commits don't.** Upstream history does not
  become part of the monorepo's ancestry, and monorepo side branches do
  not become part of upstream history.
- **Version the relationship, derive the rest.** `.splice` moves and
  branches with its folder. It records an upstream commit, never a
  monorepo commit ID that rebasing could invalidate.
- **Rebuild deterministically.** The same committed history produces the
  same upstream commits, so a later push can fast-forward without a
  monorepo commit recording the earlier push.
- **Let Git do the work.** Git parses the configuration, merges trees,
  creates commits and transfers objects. Its commands are
  [inspectable](05-git-trace.md).
- **Name the target when writing, show everything when looking.** Sync
  commands need paths or `--all`; inspection and fetch commands cover
  every splice by default. Familiar Git command names keep their meaning.
- **Follow the monorepo's branch by default.** Branch mapping, tracking
  overrides and pins choose the upstream target without a separate
  checkout per splice.
- **Refuse ambiguity and keep the design bounded.** Unrelated histories
  and unsupported paths stop with an explanation. Rare cases can be
  documented rather than complicating the ordinary workflow
  ([limits](04-safety-and-limits.md#limits)).

## The sync point

Like a subtree, a splice's files live directly in the monorepo. Like a
submodule, it records an upstream commit. But that commit is a sync point,
not an instruction to check out another repository: local commits can
change the folder while the sync point stays put.

## Vocabulary

A splice is the folder and its connection to an upstream. **Splicing in**
brings upstream content into the monorepo; **splicing out** publishes the
folder's changes upstream. The [sync model](../03-concepts/02-sync-model.md)
defines H, B, T, R and U(H); [Concepts](../03-concepts/README.md) explains
the state file, upstreams and identity.

## Architecture

<div align="center">

![Committed folder contents and .splice are separate from local fetched refs and configuration. The rebuild and sync state are derived from history and fetched commits; fetch, pull and push connect them to the upstream repository.](architecture.drawio.svg)

</div>

The relationship is committed in `.splice`. Fetched refs, upstream keys
and branch-tracking overrides are local Git data. B, R and the sync state
are computed from that state and the monorepo's history.
[Development](../10-contributing/01-development.md#code-map) maps this onto the code.

## State and upstreams

[State and upstreams](01-state-and-upstreams.md) explains why `.splice`
uses Git's config format, why refs belong to URLs rather than paths, and
how branches and pins map between repositories.

## How the commands work

Commands that change the monorepo or publish upstream changes require an
explicit target. `status`, `diff`, `log` and `fetch` cover all splices
unless paths narrow the selection. `clone` and `init` start one splice.
This keeps an overview complete and a write deliberate.

## Splicing in

`git splice merge` supplies a three-way merge base explicitly, after
re-rooting upstream trees into the monorepo's layout. Git's cherry-pick
then keeps local edits and records the new sync point in one commit.
[Splicing in](02-splicing-in.md) explains the mechanism and nested ordering.

## Splicing out

`git splice push` rebuilds the folder's history as upstream commits,
without writing to the monorepo. [Splicing out](03-splicing-out.md)
explains history boundaries, deterministic metadata and how `status`,
`diff` and `log` use the result.

## Safety and limits

Upstreams use private refs instead of Git remotes, so a plain Git push
cannot select them as a remote. [Safety and limits](04-safety-and-limits.md)
explains that choice, the rejected alternatives and the remaining limits.

## Checking what it runs

[Checking what it runs](05-git-trace.md) shows how to capture Git commands
with `GIT_TRACE` and where tracing has limits.

## Why the name "splice"

[Why the name "splice"](06-name.md) explains the rope, RNA and JavaScript
analogies behind the name.
