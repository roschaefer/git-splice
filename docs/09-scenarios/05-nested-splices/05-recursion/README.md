# Recursion

These scenarios are experiments. They show how `git-splice` is meant to
pull through [nested splices](../../../03-concepts/04-nesting.md): as
if each splice's upstream were cloned on its own, updated there, and
the result handed up to the splice around it. Some pages do it by hand,
with worktrees and plain Git; others with `git splice pull --recursive`,
which does part of it already. As the tool takes over, their code blocks
shrink to its commands, and their drawings change with them.

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

- [pulled one level at a time](../01-nested-splices/02-three-levels/pulled-level-by-level.md):
  three levels, a worktree per level, and `merge --rebuilt-commit` to
  take each result up.
- [rebased one level at a time](../01-nested-splices/02-three-levels/rebased-level-by-level.md):
  three levels with `--rebase`, each level's R rebased onto its own
  pull, so the conflict comes up once, innermost.
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
