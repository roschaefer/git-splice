# Third-party tools

Tools outside Git that also keep a library in a monorepo folder, or move
changes between a monorepo and other repositories. Each comparison takes
the [same example as Git's own tools](../01-git/README.md) until it hits
the tool's pain points, then shows how `git-splice` handles them. A page
that runs the tool prints its version.

| | [`git-subrepo`](01-git-subrepo.md) | [Josh](02-josh.md) | [`splitsh-lite`](03-splitsh-lite.md) | [Export tools](04-export-tools.md) | `git-splice` |
| --- | --- | --- | --- | --- | --- |
| Library in the monorepo | files, one commit per pull | files, with copies of the library's whole history | files | files | files, one commit per pull |
| Changes back to the library | every push also commits to the monorepo, and a squash merge or rebase strands that commit | a push sends the monorepo's commits as they are | none: a faster [`git subtree split`](../01-git/02-git-subtree.md#problem-2-with---squash-split-walks-everything) that publishes read-only repositories | a separate workflow: a pull request is imported, and closed rather than merged | `push` rebuilds the commits since the last sync |
| Best for | one upstream branch for every monorepo branch | `git bisect` and `git blame` into the library, any slice of the monorepo as a repository | publishing folders of a monorepo | one repository as the source of truth | changing a library in the monorepo and sending the changes back |
