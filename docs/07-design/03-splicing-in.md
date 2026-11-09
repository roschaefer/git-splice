# Splicing in

Git already knows how to reconcile changes with a three-way merge. The
design problem is to make that machinery work across repositories whose
histories stay separate and whose files live at different paths.

## Reuse Git's merge without joining histories

Merging the upstream branch directly would bring its ancestry into the
monorepo, and its root files would not line up with the splice's folder.
Copying its latest files would instead overwrite local edits. Neither
preserves both the independence of the repositories and the changes made
on each side.

Rebuilding the folder's commits in the upstream's layout gives those
changes an upstream history R. Git can compare R with the fetched upstream
tip T and find the history they share. This matters after a push: the
shared history can be newer than the recorded sync point, so using that
older point would treat already-published changes as new ones. After an
upstream rewrite, the branch's reflog can supply its previous fork point
([sync model](../03-concepts/02-sync-model.md#how-r-and-t-determine-the-status)).

To bring the resulting upstream changes into the monorepo, we construct
temporary commits for the base and upstream tip in the monorepo's layout.
Both keep everything outside the splice equal to `HEAD`; their difference
is confined to the folder and its sync state. Making one the parent of the
other lets `git cherry-pick` apply that change with Git's three-way merge.
These commits adapt the changes to the receiving repository without
joining the upstream ancestry to it.

The purpose of rebuilding is therefore broader than preparing a push:
it gives Git a shared history for reasoning about changes across the
repositories. Git remains responsible for merging, rename detection and
conflicts. Using its cherry-pick also provides familiar recovery tools
instead of requiring a separate conflict protocol
([conflict recovery](../06-command-reference/05-pull.md#conflicts)).

## Record accepted history even when the files match

File equality alone cannot tell us which history has been accepted.
Upstream may squash or rewrite published commits, or accept an edited
rebuild with the same files. Without recording that accepted upstream
commit, a later rebuild could publish the original commits again.
This is why a pull can need a state-only commit
([rewritten history](../09-scenarios/06-rewritten-history/02-upstream-rewritten-equal-tree/README.md),
[edited rebuild](../09-scenarios/06-rewritten-history/01-edited-before-push/README.md)).

Including the sync-state update in the same merge as the files keeps the
recorded relationship tied to the result the user accepts. An ordinary
push needs no such recording commit: R and T already agree.

## Preserve existing work without inventing shared history

When an existing folder differs from upstream, overwriting it would lose
local work. But treating its old contents as a shared base would also be
an assumption: those files may never have come from that upstream.
`clone --merge` therefore uses an empty folder as the base. Git then keeps
local-only files and exposes competing additions as conflicts for the user
to resolve.

Deleting and re-cloning on a branch is not equivalent. The later Git merge
still has the old folder in its base and can discard local-only files.
Refusing a differing folder unless `--merge` is requested avoids making
that decision implicitly. The command names also preserve Git's existing
vocabulary: `add` already means staging changes.

Starting an upstream from an existing folder poses a separate question:
which earlier monorepo changes were intended for publication? `init`
cannot infer that intent, so the publication history starts there, rather
than exposing everything that previously occupied the folder
([history before init](../09-scenarios/02-starting-a-splice/04-init-new-upstream/01-removed-before-init/README.md)).

## Respect the dependencies between nested relationships

An outer pull can change the inner `.splice`, including which upstream
commit it records. Merging the inner splice first would use a relationship
that the outer merge may replace. Top-down merging establishes the
containing state first, preserving the meaning that the inner splice
would have in a standalone clone of its enclosing upstream.

The same reasoning requires fetching newly referenced inner commits:
a complete outer pull must leave its nested state inspectable. Fetching
those commits does not imply choosing to merge further inner changes;
that choice remains explicit
([recursive pull](../06-command-reference/05-pull.md#--recursive)).

Publication has the reverse dependency. An enclosing upstream must not
record an inner commit that a standalone clone cannot fetch. Inner commits
must therefore be published before the enclosing relationship. A failed
prerequisite blocks dependent operations rather than allowing a partial
sync to claim a relationship it could not establish.
