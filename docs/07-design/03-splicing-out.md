# Splicing out

## Splicing out: `push` and the rebuild

`git splice push` publishes the folder's history as upstream commits,
without writing a monorepo commit. R is derived from committed history,
so the same input rebuilds to the same commit IDs. The
[sync model](../03-concepts/02-sync-model.md) explains B, U(B), R and T;
this page explains why publication uses a deterministic, bounded rebuild.

`rebuild_splice` follows three steps:

1. **Find the last sync.** L is the newest first-parent commit changing
   this splice's `.splice`, following its ID through moves. U(L) is the
   upstream commit recorded there.
2. **Find the starting history.** If L's folder without `.splice` equals
   U(L)'s tree, L is B. Otherwise L also contains local changes and must
   itself be rebuilt; the walk continues back to B. A splice with no
   recorded upstream commit starts at its mount instead
   ([boundary rules](../03-concepts/02-sync-model.md#where-b-is)).
3. **Copy folder changes.** Walk first-parent commits in order, at the
   paths the splice occupied, and create upstream commits with
   `git commit-tree`. A monorepo merge becomes one ordinary upstream
   commit: upstream does not need the monorepo's side branches. Rebuilt
   pulls can still introduce upstream merge parents
   ([parent rules](../03-concepts/02-sync-model.md#parents-of-rebuilt-commits)).

### Deterministic metadata

Each copy excludes the splice's own `.splice` and keeps author, committer,
both dates and message. Message bytes pass through without an added
newline; NUL separators keep the batched log's record framing out of the
message. Copies are not signed, because signatures would make repeated
rebuilds differ.

This follows `git subtree split`'s metadata copying, but deliberately
uses first-parent history. The
[test oracle](../10-contributing/01-development.md#git-subtree-split-as-the-test-oracle)
checks identical hashes where the algorithms agree and records their
approved differences.

## History scope

A splice's history starts at its *mount*, the newest first-parent start
whose parent had no `.splice` of the same ID, after following moves to
their old paths. It excludes the folder's earlier monorepo history and any
different splice that previously occupied the path.
Moving the folder or changing its upstream URL preserves the ID and does
not create a new mount
([before init](../09-scenarios/02-starting-a-splice/04-init-new-upstream/01-removed-before-init/README.md),
[swapped paths](../09-scenarios/07-moved-folders/02-swapped-splices/README.md),
[replaced splice](../09-scenarios/02-starting-a-splice/04-init-new-upstream/02-unspliced-then-cloned-again/README.md)).

### History inherited through nesting

A nested splice may have history squashed into the monorepo by an outer
clone or pull. Rebuilding recovers that history from the enclosing upstream,
provided it contains the same splice ID. Among enclosing splices it chooses
the newest last sync, taking the outermost on a tie: an intermediate
`.splice` can lag behind changes already pushed further out. It must also
preserve a separately updated inner synced commit.

Local history from before that outer sync is joined in even when its
files match the inherited rebuild, so commits pushed directly to the inner
upstream are not lost
([inherited history](../09-scenarios/05-nested-splices/01-nested-splices/spliced-elsewhere.md),
[three levels](../09-scenarios/05-nested-splices/01-nested-splices/02-three-levels/README.md),
[joined history](../09-scenarios/05-nested-splices/01-nested-splices/pushed-and-made-above.md)).

The commit walk is bounded by the selected boundary. Metadata and folder
trees are read in batches with `git log` and `git cat-file --batch-check`;
creating the copies still needs `commit-tree` calls.
[`pull --bump`](../04-advanced-workflows/03-bump.md) can shorten later rebuilds.

## New upstream branches

A push creates a missing feature branch only if R contains commits the
upstream's default target lacks, as a PR would show. Starting a monorepo
feature branch therefore does not create empty branches in every upstream.

Commits inherited from a stacked feature branch still count, even if
nothing new changed in this splice. The first push after `init` also counts:
there is no upstream branch yet
([stacked branch](../09-scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/01-feature-branch-changed/01-stacked-branch/README.md)).

## Inspection should predict publication

Inspection and publication must agree on what would cross the splice.
`status`, `diff` and `log` therefore compare the same rebuilt history with
the fetched upstream target, rather than inventing a second interpretation
of local changes. A missing feature branch should still give a useful PR
comparison against its default target.

Equal file trees can avoid an expensive rebuild when classifying sync
state. Missing fetched objects must instead remain distinguishable from
an up-to-date splice: absence of evidence is not evidence of equality.
The [sync model](../03-concepts/02-sync-model.md#how-r-and-t-determine-the-status)
defines those states.

The presentation follows Git's ours/theirs convention and shows commit
authors because publishing history also publishes identity. Exact output
and options belong in the [command reference](../06-command-reference/README.md).
