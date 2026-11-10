# Recursion

These scenarios show how `git-splice` pulls through
[nested splices](../../../03-concepts/04-nesting.md): as if each
splice's upstream were cloned on its own, updated there, and the result
handed up to the splice around it. Pages that did that by hand, one
level at a time with a worktree per level, showed it ends where the
monorepo's own pull ends; `git splice pull --recursive` and
`pull --rebase --recursive` do it now, and the pages below show those.

## The tree

A splice and the splices inside it form a tree. Its root is the
monorepo, every other node a splice, and the edge from a parent to a
child is the child's `.splice` in the parent's folder: which upstream
the child comes from, and at which commit, its synced commit. Each
splice's history is computed from the monorepo's: its
[rebuild](../../../03-concepts/02-sync-model.md), R.

## The passes

A pull goes through the tree three times:

| Pass | Does | Order | Conflicts |
|---|---|---|---|
| discover | fetches each upstream, and reads the `.splice` files in it for the ones inside | parent before its children | none |
| merge | merges each upstream into its parent's version of the folder | parent before its children | at most one per splice |
| take up | puts each new commit into its parent's folder | children before their parent | none |

The parent goes first, since its upstream decides which splices are
inside it, and which commit of each: a newer base for the child's merge,
which then doesn't ask a question the parent's merge already answered.
The first conflict stops the pull, until it's resolved. A take-up can't
conflict: the parent's folder hasn't changed since the child's merge
started from it.

## How many conflicts

A pull through E splices, with C commits of the monorepo's own on top:

| | At most | Why |
|---|---|---|
| merge | E | one merge per splice: base its synced commit, ours its head, theirs its upstream |
| `--rebase` | E + C | the pulls, top-down, then each commit of the monorepo's own, replayed once |

## The scenarios

- [every level conflicts](../01-nested-splices/02-three-levels/every-level-conflicts.md):
  three levels, where every upstream changed the folder of the splice
  inside it: one conflict per edge, each resolved in the parent of the
  two, and each take-up conflict-free.
- [a recursive pull](01-recursive-pull/README.md): a tree with branches,
  `vendor/a/` with `b/`, `c/` in it, `d/` and `e/`, pulled with three
  runs of `pull --recursive`, each to the next conflict, and one commit
  for all of it.
- [discovered top-down](01-recursive-pull/discovered-top-down.md): why
  the splice above goes first: its pull drops `d/` and adds `e/`, so
  naming `vendor/a/d` beside it means nothing definite.
- [rebased](01-recursive-pull/rebased.md): the recursive pull with
  `--rebase`: the pulls first, as one commit, then the monorepo's own
  commit, rebased onto it once.
- [status and push](01-recursive-pull/status-and-push.md): a push goes
  bottom-up, and each parent has to record what its child's upstream has
  before it's pushed itself; `push --all` doesn't, and `status` doesn't
  notice.
- [a failed push below](01-recursive-pull/failed-push-below.md): the
  upstream above records a commit the one below never got; a clone of it
  makes the commit again and counts it as its own.
