# Comparisons

`git submodule` and `git subtree` are what Git offers for a library inside
a monorepo. These pages run both side by side with `git-splice`, on the
same library and monorepo, and show where each one's model gets in the way
of fixing a library together with your app and sending the fix back. Each
also says where it is the better tool.

- [`git submodule`](git-submodule.md): the monorepo doesn't see the
  library's files, every fix takes two commits and two pushes in the
  right order, and a second worktree has its own submodule clones but
  shares the monorepo's `submodule.*` settings for them.
- [`git subtree`](git-subtree.md): either the library's whole history
  comes into the monorepo, or `split` walks the monorepo's whole history
  on every push. Either way, the history isn't linear. A splice's sync
  point survives a [squash merge](../scenarios/03-branches-and-teamwork/03-squash-merged-pull/README.md),
  and a [merge in the monorepo](../scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/02-merge-in-monorepo/README.md)
  reaches the upstream as one commit.

| | `git submodule` | `git subtree` | `git-splice` |
| --- | --- | --- | --- |
| Library files in the monorepo | no, a gitlink | yes | yes |
| `status`, `diff`, `log` of library files | `status`: never; `diff`, `log -p`: with `--submodule=diff`; `log -- <file>`: never | yes | yes |
| Fix to app and library | two commits, two pushes, library first | one commit | one commit |
| Library history in the monorepo | none | whole, or squashed into a merge | none, one commit per sync |
| Monorepo history | linear | merges | linear |
| Push walks | nothing, the library is its own repository | the monorepo's history since the last known library commit | the commits since the boundary |
| Second worktree | initialize again, `submodule.*` settings shared, can't be moved | works | works |
| Best for | libraries kept apart, with their own access | moving a repository in for good, history included | changing a library in the monorepo and sending the changes back |

[Third-party tools](third-party/README.md) compares git-subrepo,
Josh, splitsh-lite and Copybara.
[Version control systems](vcs/README.md) compares Sapling and Jujutsu,
which work in a Git repository, and `git-splice` running next to them.

## The output is real

As on every page with output, [scrut](../../docs/sandbox.md#the-output-is-real)
runs the commands. Here [`scrut-setup.sh`](scrut-setup.sh) builds the
library and the monorepo, and the work directory shows as `$COMPARISON`.
