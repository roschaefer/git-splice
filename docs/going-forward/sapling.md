# Sapling

[Sapling](https://sapling-scm.com/) (`sl`) can work in a Git repository,
and `git-splice` runs next to it there
([comparison](../../test/comparisons/vcs/sapling.md)). Its `sl subtree`
also records sync points, in the commit instead of a file. This page says
what `git-splice` could do about both. None of it is planned yet.

## Next to `sl`

- **The current branch.** `sl commit` keeps Git on its branch, but
  `sl goto` leaves `HEAD` detached, and `sl goto main` goes to
  `origin/main`, not the local branch. That's the question
  [Jujutsu](jj.md#two-branches) raises for every commit, and the same
  answers would do.
- **Git's index after `sl amend`.** Git keeps the file as it was before
  the amend, staged, and `git-splice` warns about uncommitted changes.
  The fix belongs in Sapling
  ([sapling#1316](https://github.com/facebook/sapling/issues/1316)).
  `git-splice` shouldn't reset the index, since staged changes are the
  user's.
- **A Sapling clone.** `sl clone` makes a repository with no Git
  working copy, where Git commands don't work. `git-splice` is out of
  reach there.

## Sapling's records

`.splice` and Sapling's header record the same facts: the library's URL,
its commit, and the folder. In a Git repository, the header is called
`test_subtree`, and `subtree.use-prod-subtree-key` switches to `subtree`,
so the format may still change.

- **Turn an import into a splice.** `clone --from-submodule` turns a
  submodule into a splice. The same could read the folder's newest
  Sapling record and write `.splice` from it: the library's commit is the
  sync point, and nothing has to be fetched again. After that, `push`
  sends the monorepo's fixes back, which `sl subtree` can't.
- **Read the record instead of `.splice`.** `push` and `pull` need only
  the sync point, the folder and the URL. They could take them from the
  newest Sapling record, so a folder imported with `sl` syncs both ways
  without a `.splice`. A squash merge
  [drops the record](../../test/comparisons/vcs/sapling.md#a-squash-merge-drops-the-record),
  and an older one would give the wrong sync point, so `git-splice`
  would have to refuse where Sapling falls back.
- **Write the record too.** A pull could add the header to its commit,
  so a later `sl subtree merge` starts from it. Git can write such a
  commit (`git hash-object -t commit`), but `git commit` can't, and the
  header's format is Sapling's to change.
