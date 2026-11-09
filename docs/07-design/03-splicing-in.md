# Splicing in

## Reuse Git's merge without joining histories

The goal is to carry changes across repositories while keeping their
histories independent. A direct merge would import upstream ancestry;
copying files would overwrite local edits. Adapting commits to Git's
existing merge machinery avoids both, without inventing another merge
algorithm or conflict protocol.

Rebuilding the folder's commits in the upstream's layout produces R,
which Git can compare with the fetched upstream tip T to find their shared
history. That gives the merge a base reflecting changes already shared
between the repositories, including earlier pushes. The
[sync model](../03-concepts/02-sync-model.md#how-r-and-t-determine-the-status)
explains how that base is selected.

Temporary commits then represent the base and upstream tip in the
monorepo's layout, differing only inside the splice and its sync state.
Making the base the parent of the incoming commit lets `git cherry-pick`
apply those changes with Git's three-way merge. Git handles edits, renames
and conflicts; the resulting monorepo commit keeps upstream ancestry out.
This is why rebuilding serves both incoming and outgoing changes.

For the surrounding behaviour, see [clone](../06-command-reference/01-clone.md#--merge),
[init](../06-command-reference/08-init.md),
[sync-state updates](../09-scenarios/06-rewritten-history/02-upstream-rewritten-equal-tree/README.md)
and [nested ordering](../03-concepts/04-nesting.md#each-splice-syncs-with-the-monorepo).
