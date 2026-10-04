# Comparisons

`git submodule` and `git subtree` are what Git offers for a library inside
a monorepo. These pages run both side by side with `git splice`, on the
same library and monorepo, and show where each one's model gets in the way
of fixing a library together with your app and sending the fix back. Each
also says where it is the better tool.

- [`git submodule`](git-submodule.md): the monorepo doesn't see the
  library's files, every fix takes two commits and two pushes in the
  right order, and a second worktree has its own submodule clones but
  shares the monorepo's `submodule.*` settings for them.
- [`git subtree`](git-subtree.md): either the library's whole history
  comes into the monorepo, or `split` walks the monorepo's whole history
  on every push. Either way, the history isn't linear.

| | `git submodule` | `git subtree` | `git splice` |
| --- | --- | --- | --- |
| Library files in the monorepo | no, a gitlink | yes | yes |
| `status`, `diff`, `log` of library files | only with extra options | yes | yes |
| Fix to app and library | two commits, two pushes, library first | one commit | one commit |
| Library history in the monorepo | none | whole, or squashed into a merge | none, one commit per sync |
| Monorepo history | linear | merges | linear |
| Push walks | nothing, the library is its own repository | the monorepo's history since the last known library commit | the commits since the last sync |
| Second worktree | initialize again, `submodule.*` settings shared, can't be moved | works | works |
| Best for | libraries kept apart, with their own access | moving a repository in for good, history included | changing a library in the monorepo and sending the changes back |

The [design](../../docs/design/README.md#how-it-compares) compares more
tools in short.

## The output is real

[scrut](https://facebookincubator.github.io/scrut/) runs every command on
these pages and compares what it prints, in CI too (`just docs-check`). A
hidden first block sources [`scrut-setup.sh`](scrut-setup.sh), which
builds the library and the monorepo, fixes the commit dates and ignores
your git config, so commit hashes are the same on every run. The work
directory shows as `$COMPARISON`.
