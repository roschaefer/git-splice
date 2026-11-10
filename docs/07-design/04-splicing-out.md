# Splicing out

## Determinism avoids bookkeeping after publication

Recording every push in the monorepo would add commits just to remember
what was published. Reconstructing the same upstream commits instead lets
their IDs establish what upstream already has, so another push can
fast-forward without a second record to maintain. This is an application
of the [minimum-state principle](README.md#principles).

Using the original commit metadata avoids introducing the current time or
the identity of whoever happens to run the rebuild. Signing the copies
would introduce another source of variation, so rebuilt commits remain
unsigned. The [sync model](../03-concepts/02-sync-model.md#r-is-computed-not-stored)
defines the resulting history; the
[test oracle](../10-contributing/01-development.md#git-subtree-split-as-the-test-oracle)
checks that metadata copying agrees with `git subtree split` where their
algorithms apply alike.

## Keep monorepo branch topology out of upstream

A monorepo merge integrates a branch that may concern many projects.
Upstream needs the resulting changes to its folder, not a reconstruction
of that branch's entire development. Walking first-parent history treats
the merge as the point where those changes joined the monorepo branch.
The tradeoff is deliberate: the upstream copy preserves the integrated
change, rather than the individual commits of the merged side branch.

An upstream history imported by a pull is different: it already belongs
to that upstream and must remain connected to the rebuilt local changes.
This is why rebuilt pulls can retain upstream merge parents even though
ordinary monorepo merges become single commits
([parent rules](../03-concepts/02-sync-model.md#parents-of-rebuilt-commits)).

## Publish only history belonging to this splice

A folder's earlier contents may never have been intended for publication,
and a different library may previously have occupied the same path.
Starting at the splice's introduction and following its identity prevents
that unrelated history from being published. A move must preserve the
history; replacing the splice must not inherit its predecessor's
([identity](../03-concepts/03-splice-identity.md)). The splice's own `.splice`
is excluded because it describes its relationship to the containing
repository, not part of the upstream project itself.

## Recover nested history so enclosing imports do not erase it

An outer clone or pull can squash the inner history into one monorepo
commit. Rebuilding only that visible history would give a different result
from working in a standalone clone of the enclosing upstream. Recovering
the inner history from that upstream preserves the
[nesting principle](README.md#principles). The rebuild must also retain
history published directly to the inner upstream: equal files do not make
those commits interchangeable
([joined history](../09-scenarios/05-nested-splices/01-nested-splices/pushed-and-made-above.md)).

## Advancing sync points bounds repeated work

Without an advancing starting point, each rebuild would revisit more
history as the monorepo ages, even when each publication is small.
[`git subtree split --squash`](../05-comparisons/01-git/02-git-subtree.md#problem-2-with---squash-split-walks-everything)
demonstrates the cost; `--rejoin` shortens the walk by adding a merge.

Deriving a starting point from recorded sync state avoids that bookkeeping
merge. Advancing the state still requires a monorepo commit, so it remains
separate from publication: a pull, or an explicit
[`pull --bump`](../04-advanced-workflows/03-bump.md), can trade that commit for
less work on subsequent rebuilds.

## Inspection must predict publication

Separate interpretations of local changes could make inspection promise
something different from what a push sends. Comparing the same rebuilt
history for both keeps inspection useful as a preview, rather than merely
a report of file differences. Output conventions and sync-state definitions
belong in the [command reference](../06-command-reference/README.md) and
[sync model](../03-concepts/02-sync-model.md#how-r-and-t-determine-the-status).
