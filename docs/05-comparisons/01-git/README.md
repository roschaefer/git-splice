# Git's own tools

Each comparison takes one example through a tool until it hits the
tool's pain points, then shows how `git-splice` handles them in the same
example. The example is a monorepo with an app that uses a library,
`https://git.example.com/lib.git`, with 30 commits. You put the library
into a folder of the monorepo, fix it together with the app, send the
fix back, and take in the library's own changes.

Git comes with two tools for this, compared with `git-splice` point by
point:

| | [`git submodule`](01-git-submodule.md) | [`git subtree`](02-git-subtree.md) | `git-splice` |
| --- | --- | --- | --- |
| Library files in the monorepo | no, a gitlink | yes | yes |
| `status`, `diff`, `log` of library files | `status`: never; `diff`, `log -p`: with `--submodule=diff`; `log -- <file>`: never | yes | yes |
| Fix to app and library | two commits, two pushes, library first | one commit | one commit |
| Library history in the monorepo | none | whole, or squashed into a merge | none, one commit per sync |
| Monorepo history | linear | merges | linear |
| Push walks | nothing, the library is its own repository | the monorepo's history since the last known library commit | the commits since the boundary |
| Second worktree | initialize again, `submodule.*` settings shared, can't be moved | works | works |
| Best for | libraries kept apart, with their own access | moving a repository in for good, history included | changing a library in the monorepo and sending the changes back |
