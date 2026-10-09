# Third-party tools

Tools outside Git that also keep a library in a monorepo folder, or move
changes between a monorepo and other repositories. The pages run on the
same library and monorepo as [`git submodule` and `git subtree`](../README.md).
A page that runs the tool prints its version.

## How it compares

| Tool | What is similar | Key difference |
| --- | --- | --- |
| [git-subrepo](https://github.com/ingydotnet/git-subrepo) | It has a committed state file, fetches by URL and pulls as one commit. | It stores a monorepo commit that rebases and squash merges can invalidate, and fixes each folder to one upstream branch. ([in depth](git-subrepo.md)) |
| [splitsh-lite](https://github.com/splitsh/lite) | It publishes folders as repositories. | It creates read-only mirrors; changes only flow out. |
| [Josh](https://github.com/josh-project/josh) | It exposes part of a monorepo as a repository, and a push sends the same commits, if they're unsigned. | The monorepo has to hold copies of the library's whole history, since its filtered view meets the library at shared commits; a pull adds a commit for each upstream commit. ([in depth](josh.md)) |
| [Copybara](https://github.com/google/copybara) | It moves changes between repositories. | One repository is the source of truth; syncing back needs a separate reverse workflow ([in depth](copybara.md)). |
