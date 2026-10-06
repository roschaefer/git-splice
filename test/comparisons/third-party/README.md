# Third-party tools

Tools outside Git that also keep a library's files in a monorepo folder
and sync them with the library's own repository. They run on the same
library and monorepo as [`git submodule` and `git subtree`](../README.md),
at the version the page prints.

- [git-subrepo](git-subrepo.md): like a splice, the folder's files are
  ordinary monorepo files and every pull is one commit, so the history
  stays linear. But a folder syncs with one library branch whatever the
  monorepo's branch, every push writes a monorepo commit, and after a
  squash merge or rebase the next push stops until `.gitrepo` is fixed
  by hand.

| | git-subrepo | `git splice` |
| --- | --- | --- |
| Monorepo history | linear | linear |
| Commits per sync | one per pull, one per push | one per pull |
| Library branch | the one in `.gitrepo`, for every monorepo branch | the monorepo branch's name |
| Sync point | a monorepo commit, stored in `.gitrepo` | derived: the newest commit that changed `.splice` |
| After a squash merge | push stops until `.gitrepo` is fixed by hand | push works |
| After rebasing pushed commits | push stops until `.gitrepo` is fixed by hand | diverged, `push --force` as with Git |
