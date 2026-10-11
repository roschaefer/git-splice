# Weak parents

A thought experiment, not a plan: what the sync point U would be if Git
could record it, and who has proposed something like it before. Nothing
here changes how git splice works.

## The sync point is a parent, written into the tree

B, the commit that wrote U into `path/.splice`
([sync model](../../test/concepts/sync-model/README.md)), could have
been a merge instead, with two parents: the monorepo's previous commit,
and U. Its tree would be the same: the monorepo, with U's files in
`path/`. That's the commit `git subtree add` and `git subtree pull`
create ([`git subtree` compared](../../test/comparisons/git-subtree.md)).

Both record one fact: the folder continues U. A second parent records it
in the commit graph, `.splice` as content of the tree. The fact is the
same, but different tools see it:

| | U as a second parent | `commit = U` in `.splice` |
|---|---|---|
| Who sees it | Git: `log`, `merge-base`, `bisect` and `blame` walk into the library's history | Only git splice. To Git, it's a line in a file, and the monorepo's history stays linear |
| U's objects | Required: every clone of the monorepo fetches U and all its ancestors, and `gc` keeps them | Optional: git splice fetches U when it needs it |
| Which folder | Git doesn't know: U has the library at its root. `git subtree` needs `--prefix`, and with several splices, which parent belongs to which folder | Where the file is. `git mv` moves it along |
| Finding the current U | Search the history for the newest such merge | Read one file at `HEAD` |
| Rebase, squash merge | Lost: `rebase` drops merges, a squash merge keeps one parent | Kept: both keep the tree |
| The merge base for a pull | `git merge-base` finds U | git splice reads U, and uses it as the base |

The second-to-last row is the reason for the file. Every way of
rewriting history keeps a commit's tree, and most drop or rewrite
everything else.

The two also don't claim the same. A merge says U's whole history is
part of the monorepo's. `.splice` says only that the folder's files came
from U: changes cross the boundary, commits don't.

## A weak parent in Git

Between the two, there could be a third: a **weak parent**. It's
recorded in the commit, like a parent, but it's not part of the commit's
history, like the line in `.splice`:

- `log`, `merge-base` and `rebase` don't follow it.
- A fetch doesn't send its target, and a missing target isn't an error.
- `gc` keeps its target, if it's there.

Git has none, and the idea has come up before.

### The `origin` RFC, 2008

In September 2008, Stephen R. van den Berg proposed an `origin` header
for commits made by `cherry-pick` and `revert`
([thread](https://lore.kernel.org/git/20080909194354.GA13634@cuci.nl/T/)).
His motivation was backports among seven branches: when you change code
that was cherry-picked, you want to find the other copies. The rules he
proposed are those of a weak parent:

> In an existing repository gc/prune shall not delete commits being
> referred to by origin links.
>
> During fetch/push/pull the full commit including the origin fields is
> transmitted, however, the objects the origin links are referring to
> are not
>
> git fsck will traverse origin links, but will stay silent if the
> object an origin link points to is unreachable
>
> git merge disregards the whole origin field entirely

Jakub Narębski summed it up as a link that protects against pruning,
"but it is not considered an error for it to be broken". Following
Paolo Bonzini, the header became a pair, `origin <sha1> <sha2>`: a
change is the difference between two commits, not one commit.

It wasn't merged. The objections, and how they apply to a splice:

- **Linus Torvalds** objected that cherry-picks, squashes and
  `rebase -i` are how people clean up history, so their origins
  shouldn't be recorded. And data a fetch doesn't send is local, so "they
  should not be in the object database at all". The link would be
  "unreliable, random, and depends on the phase of the moon". For a splice, the
  target is the other way round: not local, but a commit of another
  repository, and the link has to survive the clean-up.
- **Petr Baudis** objected that "cherrypicks can be from completely
  unrelated histories". For a splice, that's the normal case: U is in
  the library's history, not the monorepo's.
- **Theodore Ts'o** pointed to `git cherry-pick -x`, which records the
  source in the message, as `(cherry picked from commit …)`. That's
  still Git's answer: a weak link as text, for people and scripts to
  parse.

Since then, Git has gained
[partial clone](https://git-scm.com/docs/partial-clone): a repository
may lack objects it refers to, and fetch them from a *promisor remote*
when needed. A weak parent wouldn't be the only reference to a missing
object any more.

### Fossil's Q cards

[Fossil](https://fossil-scm.org/home/doc/trunk/www/fileformat.wiki)
has had one since 2011. A check-in lists its parents in a P card, and
cherry-picks and backouts in Q cards: `+target` or `-target`, with an
optional baseline, the same pair of commits as in the `origin` RFC. A Q
card names a predecessor that isn't an ancestor.

### Submodules

A submodule's gitlink is a weak link that Git has: a commit id in the
tree that the repository doesn't need to have. Like `.splice`, it's in
the tree, not in the commit, so it survives a rebase. Unlike `.splice`,
it says what to check out, not where the folder's files came from
([the sync point](../design/README.md#the-sync-point)).

## What a splice would need

Every proposal above links commits of one repository. A splice links a
folder to a commit of another one, so a weak parent for it needs more
than a commit id:

- **the target**, U,
- **the folder** it maps to, which `git subtree` passes as `--prefix`,
- **where to fetch it from**, which object ids alone don't say.

And it has to survive the squash merges and rebases that Linus listed,
which only the tree does. That's what `.splice` holds: the URL, and U,
in the folder they belong to.
