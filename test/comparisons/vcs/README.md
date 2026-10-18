# Version control systems

Sapling and Jujutsu are version control systems that can work in a Git
repository: `sl` and `jj` read and write `.git/`, and Git commands still
work. So `git-splice` can run next to them, within limits. The pages run
each one on the same library and monorepo as
[`git submodule` and `git subtree`](../README.md).

- [Sapling](sapling.md): `sl subtree` imports a repository into a
  folder and merges its changes, recording the sync point in each
  commit's metadata, and sends nothing back.
- [Jujutsu](jj.md): jj has nothing built in for a library in a folder
  yet, and doesn't see inside submodules. A splice is files to jj, but
  `git-splice` needs Git back on a branch first.

| | Sapling | Jujutsu |
| --- | --- | --- |
| In a Git repository | `.git/sl/` next to Git's data; `sl clone` makes a repository without it | colocated: `.jj/` next to `.git/` |
| Library in a folder | `sl subtree import` and `merge` | none released |
| Sync point recorded | in each commit's metadata, an extra header to Git | none |
| Changes back to the library | a patch by hand | none |
| Git's `HEAD` | on the branch after `sl commit`, detached after `sl goto` | detached at `@-` after `jj commit` or `jj new` |
| `git-splice` next to it | works on a branch; `sl amend` leaves Git's index behind | works after `jj bookmark set` and `git checkout` |
| What `git-splice` could do | [Sapling](../../../docs/going-forward/sapling.md) | [Jujutsu](../../../docs/going-forward/jj.md) |
