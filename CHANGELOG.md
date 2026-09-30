# Changelog

## [0.1.1](https://github.com/roschaefer/git-subtrees/compare/v0.1.0...v0.1.1) (2026-09-30)


### Bug Fixes

* **init:** refuse a monorepo without commits up front ([#46](https://github.com/roschaefer/git-subtrees/issues/46)) ([098ca03](https://github.com/roschaefer/git-subtrees/commit/098ca03a7179f28526b39f5ec7023a661a9b6fe7)), closes [#45](https://github.com/roschaefer/git-subtrees/issues/45)

## 0.1.0 (2026-09-28)

First release. `git subtrees` keeps the `git subtree` folders of a monorepo
in sync with their own repositories, without a config file: a subtree is any
remote named like a folder, and each branch syncs with the branch of the
same name on every remote.

### Features

* `status` shows every subtree's sync state: never fetched, up to date,
  push, pull, diverged, unrelated history, or no branch on the remote.
* `diff` shows the changes `push` would send.
* `fetch` fetches every subtree's remote in parallel and reports when the
  matching branch moved.
* `merge` squash-merges already-fetched changes; `pull` is `fetch` plus
  `merge`.
* `push` splits and pushes the subtrees that changed. It creates a missing
  remote branch only if the subtree changed on the current branch.
* `prune` removes stale remote-tracking refs of subtree remotes.
* `init` sets up a subtree: it adds the remote's content, adopts a folder
  copied in by hand, or, on a branch the remote lacks, starts from the
  remote's base branch.
* `--version`, and completions for bash, zsh and fish.

### Installation

* `nix profile install github:roschaefer/git-subtrees`, which brings its own
  Bash, Git and completions, or clone and symlink as the README describes.
* Without Nix, it needs Bash >= 4.4 and a git that ships `git subtree`.
