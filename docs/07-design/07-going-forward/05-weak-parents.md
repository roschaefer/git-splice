# Weak parents

Native support for weak parents would give the provenance recorded in
`.splice` a place in the VCS itself. The
[overview](README.md#what-the-vcs-could-provide) defines the term and shows
how the file represents a weak parent today.

## What a weak parent would need

- Merges would not treat it as another source of files.
- Provenance-aware `blame`, `bisect` and `log` could resolve it into the
  upstream's history, without requiring every history walk to follow it.
- Fetches would not need to send its target; a missing target would be valid.
- Garbage collection would keep the target when present.
- The URL and folder mapping would travel with the link through rewrites.

The traversal can be built on `.splice` already. Native VCS support
would make the relationship explicit to other tools, rather than require
each to interpret a file. Git has no such parent today; this is a design
possibility, not a plan to replace `.splice`.

## Earlier approaches

Stephen R. van den Berg's 2008
[`origin` RFC](https://lore.kernel.org/git/20080909194354.GA13634@cuci.nl/T/)
proposed links for cherry-picks and reverts: keep targets during garbage
collection, but don't require fetches to send them or merges to follow
them. It wasn't merged. The discussion questioned both recording origins
that users intentionally rewrite and storing links whose targets might
be missing.

A submodule's gitlink already names a commit the containing repository
needn't have. Its path and `.gitmodules` URL supply the other two facts.
But it says what to check out, rather than where editable files came from.

Sapling uses custom headers for subtree sync records; jj uses one for
change identity. Their own commands can preserve those headers across
rewrites. Plain Git and forge squash merges do not preserve them in
general. The [Sapling metadata scenario](../../09-scenarios/09-vcs-compatibility/01-sapling-metadata/README.md)
shows the consequence of losing a sync record, and lists Git's behaviour
for other rewrites.
