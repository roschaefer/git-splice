# Version control systems

Sapling and Jujutsu can share Git storage, but that leaves two separate
questions: do they sync an external repository into a folder, and can
`git-splice` run alongside them?

| | Sapling | Jujutsu |
| --- | --- | --- |
| A repository in a folder | `sl subtree` imports and merges it | No equivalent released; submodule contents are not managed |
| Sync state | Commit metadata interpreted by Sapling | No built-in folder-sync state |
| Sending folder changes upstream | No `sl subtree` export command in the tested version | No built-in folder-sync command |
| Using `git-splice` | In a Git working copy, with branch and index caveats | In a colocated working copy, after selecting a named Git branch |

- [Sapling](01-sapling.md): directory branching, sync metadata and Git rewrites.
- [Jujutsu](02-jj.md): ordinary files work, but syncing needs a named Git branch.

The executable examples pin Sapling and jj in [`flake.nix`](../../../flake.nix).
Their exact output and compatibility caveats describe those versions.
Future integration ideas live under [Going forward](../../07-design/07-going-forward/README.md).
