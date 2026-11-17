# Weak parents

Native support for weak parents would give the provenance recorded in
`.splice` a place in the VCS itself. The
[overview](README.md#what-the-vcs-could-provide) defines the term and shows
how the file represents a weak parent today.

## A merge parent or a file

A pull could have been a merge, with U(H) as its second parent, as
`git subtree pull` without `--squash` creates
([`git subtree` compared](../../05-comparisons/01-git/02-git-subtree.md)).
Both record that the folder continues U(H):

| | U(H) as a second parent | `commit = U(H)` in `.splice` |
|---|---|---|
| Who sees it | Git: `log`, `merge-base`, `bisect` and `blame` walk into the library's history | Only `git-splice`; the monorepo's history stays linear |
| U(H)'s objects | Required: every full clone fetches U(H) and its ancestors | Optional: `git-splice` fetches U(H) when it needs it |
| Which folder | Unknown: U(H) has the library at its root, so `git subtree` needs `--prefix` | Where the file is; `git mv` moves it along |
| Finding the current U(H) | Search the history for the newest such merge | Read one file at `HEAD` |
| Rebase, squash merge | Lost: `rebase` drops merges without `--rebase-merges`, and a squash merge keeps one parent | Kept, like the folder's other files |

The last row is the reason for the file. The two also claim different
things: a merge says U(H)'s whole history is part of the monorepo's;
`.splice` says only that the folder's files came from U(H).

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
