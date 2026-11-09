# Design

The preceding chapters explain what `git-splice` does and how to use it.
Design explains why: the principles, tradeoffs and constraints behind that
behaviour. Mechanisms appear here where they explain a choice; the
[sync model](../03-concepts/02-sync-model.md) defines the behaviour itself.

These principles also guide future features. Contributors, including AI
agents, should use them to evaluate proposed behaviour, not just to describe
the current implementation. A change that needs a different tradeoff should
explicitly reconsider the affected principle and its rationale.

## Principles

- **Changes cross the splice, commits don't.** Upstream history does not
  become part of the monorepo's ancestry, and monorepo side branches do
  not become part of upstream history.
- **Version the relationship, derive the rest.** `.splice` moves and
  branches with its folder. It records an upstream commit, never a
  monorepo commit ID that rebasing could invalidate. Keeping sync state
  in versioned files also avoids depending on VCS-specific commit metadata.
- **Nesting should not change a splice's meaning.** Given equivalent
  history, upstream state and settings, syncing `vendor/a/b/` should produce
  the same result for that splice as syncing `b/` in a standalone clone
  of `vendor/a`'s repository. A project should not need a different dependency workflow
  because it is embedded in another repository. This governs
  [portable state and defaults](01-state-and-upstreams.md#sync-state-belongs-in-versioned-files)
  and [inherited history](03-splicing-out.md#history-inherited-through-nesting).
- **Rebuild deterministically.** The same committed history produces the
  same upstream commits, so a later push can fast-forward without a
  monorepo commit recording the earlier push.
- **Ask “what would Git do?”** Git has much more experience solving
  version-control problems. Where its solution works well, implement the
  closest equivalent: local branch-tracking settings and reflogs are
  examples. This is a starting point for design decisions, not a reason to
  repeat known problems such as mixing unrelated repositories' tags in one
  namespace or adopting the submodule model
  ([state choices](01-state-and-upstreams.md),
  [submodule comparison](../05-comparisons/01-git/01-git-submodule.md)).
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

## Why record a sync point?

A folder must remain editable with ordinary Git commands between syncs.
Recording the last upstream commit gives the next merge a shared reference
without making that commit an instruction to check out another repository.
This combines files living directly in the monorepo with an explicit
upstream relationship. [Concepts](../03-concepts/README.md) defines the
state file, upstreams and identity; the
[sync model](../03-concepts/02-sync-model.md) defines H, B, T, R and U(H).

## Architecture

<div align="center">

![Committed folder contents and .splice are separate from local fetched refs and configuration. The rebuild and sync state are derived from history and fetched commits; fetch, pull and push connect them to the upstream repository.](architecture.drawio.svg)

</div>

The relationship is committed in `.splice`. Fetched refs, upstream keys
and branch-tracking overrides are local Git data. B, R and the sync state
are computed from that state and the monorepo's history.
[Development](../10-contributing/01-development.md#code-map) maps this onto the code.

## State and upstreams

- **Commit the relationship; keep fetch state local.** Shared state must
  survive history rewrites and use by other VCS tools without depending
  on their commit metadata.
- **Use Git's config format and private refs.** Reuse Git's tools without
  introducing an upstream remote that a plain push could select.
- **Identify upstreams by URL, not folder path.** Moves preserve fetched
  history; splices sharing an upstream can share its refs.
- **Commit shared defaults; keep tracking overrides local.** A personal
  branch choice stays local, following Git's branch-tracking model.

[State and upstreams](01-state-and-upstreams.md) develops these decisions.

## Why reads are broad and writes explicit

Inspection should reveal changes across the monorepo without making the
user remember every splice. Publishing or changing committed files should
require a deliberate selection. New commands should preserve that
asymmetry; the [command reference](../06-command-reference/README.md)
documents each command's targets and defaults.

## Splicing in

`git splice merge` supplies a three-way merge base explicitly, after
re-rooting upstream trees into the monorepo's layout. Git's cherry-pick
then keeps local edits and records the new sync point in one commit.
[Splicing in](02-splicing-in.md) explains the mechanism and nested ordering.

## Splicing out

`git splice push` rebuilds the folder's history as upstream commits,
without writing to the monorepo. [Splicing out](03-splicing-out.md)
explains why history boundaries and deterministic metadata matter, and
why inspection uses the same rebuilt history as publication.

## Safety and limits

Upstreams use private refs instead of Git remotes, so a plain Git push
cannot select them as a remote. [Safety and limits](04-safety-and-limits.md)
explains that choice, the rejected alternatives and the remaining limits.

## Checking what it runs

[Checking what it runs](05-git-trace.md) shows how to capture Git commands
with `GIT_TRACE`: evidence for the principle that repository operations
should remain inspectable through Git, along with that approach's limits.

## Why the name "splice"

[Why the name "splice"](06-name.md) explains the rope, RNA and JavaScript
analogies behind the name.
