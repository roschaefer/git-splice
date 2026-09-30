# git-subtrees

Manage multiple git subtrees in a monorepo: keep each folder in sync with
its own repository, to publish a package, mirror a library, or keep a
vendored copy up to date. You don't need a config file.

## The contract

A subtree is any git remote whose name is the path of a folder in your
repo:

    git remote add vendor/foo <url>    # vendor/foo is now a subtree

That's all the configuration there is. `git subtrees status` lists what it
found. Everything follows from two rules:

1. **The remote name is the folder path.** If you move the folder, also run
   `git remote rename <old-path> <new-path>`.
2. **Your local branch name is the remote branch name.** On `main`, every
   subtree syncs with its remote's `main`. On `feature-x`, every subtree
   syncs with its remote's `feature-x`.

Subtrees can't be nested: next to a subtree `vendor/pkg`, there can't be a
remote `vendor/pkg/extra`, even one without a folder. Git 2.51+ already
refuses such remote names; with older versions, every command stops with
an error and tells you how to fix it
([why](test/scenarios/nested-subtrees/README.md)).

## How it compares

`git-subtrees` is a layer on `git subtree`, not a replacement: it fills in
`--prefix`, remote and branch from [the contract](#the-contract), so one
command handles every subtree. Wherever plain Git does the job, it calls
Git, hence Bash.

Other tools keep a config of their own, and most don't follow your branch:

| Tool | Why it doesn't fit |
| --- | --- |
| `git submodule` | `git switch` doesn't switch the submodules' branches. `--recurse-submodules` only checks out a pinned commit. |
| [git-subrepo](https://github.com/ingydotnet/git-subrepo) | A `.gitrepo` file per folder. Switching branches in the monorepo doesn't switch the branch a subrepo syncs with. |
| [splitsh-lite](https://github.com/splitsh/lite) | One way only: it publishes read-only mirrors. |
| [Josh](https://github.com/josh-project/josh) | The opposite model: the monorepo is authoritative, and people work in filtered views of it. |
| [Copybara](https://github.com/google/copybara) | One repository is the source of truth. Syncing back needs a second, reverse workflow. |

## Example

[A walkthrough of every command](walkthrough/README.md) shows what each one
prints, on a throwaway monorepo whose subtree remotes live on the same
machine. To follow along, run `just walkthrough` in a clone of this
repository.

## Commands

Each command applies the familiar Git operation to every subtree at once,
using your current branch name as the branch on each remote. You can also
pass paths to limit it to some subtrees. Run `git subtrees <command> --help`
for options.

| Subcommand | `git` | `git subtrees` |
| --- | --- | --- |
| `status` | Summarizes the **current worktree and branch**. | Summarizes the [sync state](#sync-states) of **every selected subtree and its remote branch**. |
| `diff` | Shows worktree changes that could be **committed**. | Shows committed subtree changes that would be **pushed**. |
| `fetch` | Updates remote-tracking refs from **one remote**. | Updates remote-tracking refs from **every selected subtree remote**, calling out when the matching branch moved. |
| `merge` | Joins **already-fetched** history into the current branch. | Squash-merges **already-fetched** remote changes into **every selected subtree directory**, without touching the network. |
| `pull` | `fetch` + `merge` for the **current repository**. | `fetch` + `merge` for **every selected subtree**. |
| `push` | Pushes the **current repository's refs** to a remote. | Splits and pushes **every selected locally changed subtree** to its matching remote. |
| `prune` | (`git remote prune`) Removes stale tracking refs for **one remote**. | Removes stale tracking refs for **every selected subtree remote**. |
| `init` | Initializes the **current directory** as a Git repository. | Initializes **one path/remote pair inside the monorepo** as a managed subtree (see below). |

`status`, `diff` and `merge` only use what was last fetched. Run
`git subtrees fetch` first if you need the latest remote state.

**Pushing a new branch.** If a subtree's remote doesn't have your branch
yet, `push` creates it only when that subtree changed on your branch. So
starting a feature branch doesn't create empty branches on every remote.
"Changed" is measured against the monorepo's base branch. That's `--base
<branch>` if you pass it, else `origin/HEAD`, else `init.defaultBranch`.
If none of these work, `push` asks for `--base` instead of guessing.

**Setting up a subtree.** `git subtrees init <path> <url>` adds the remote
if it's missing. It never changes the URL of an existing remote. If
`<path>` doesn't exist yet, it runs `git subtree add` to bring in the
remote's content. On a branch the remote doesn't have yet, it adds the
remote's base branch instead (found like for `push`), and your first `push`
creates your branch on top of it. If the remote has neither (e.g. it's
still empty), `init` only registers the remote. If `<path>` already has
exactly the remote's content, e.g. copied in by hand, `init` records that
as the last sync, so later pushes build on the remote's history. If it has
content that isn't related to the remote, `init` stops and asks you to move
the folder aside and merge it back by hand.

## Sync states

`status` reports one of these states for each subtree, and `merge`, `pull`
and `push` act on it. Each linked scenario is a small, tested example of that
state.

| State | Meaning | What to do |
| --- | --- | --- |
| never fetched | The remote was added but never fetched. ([example](test/scenarios/not-connected/README.md)) | Run `git subtrees fetch`. |
| up to date | Both sides are the same. ([example](test/scenarios/up-to-date/README.md)) | Nothing to do. |
| push | Only your side changed. ([example](test/scenarios/push-ahead/README.md)) | Run `git subtrees push`. |
| pull | Only the remote changed. ([example](test/scenarios/pull-ahead/README.md)) | Run `git subtrees pull`. |
| diverged | Both sides changed since the last sync. ([example](test/scenarios/diverged-common-ancestor/README.md)) | Run `git subtrees pull`, then `push`. On a conflict, resolve it and `git commit` first. |
| unrelated history | Both sides changed and share no history, e.g. the remote was rebuilt from scratch. ([example](test/scenarios/diverged-unrelated-history/README.md)) | Pick a side. `merge`, `pull` and `push` refuse to guess and print the commands to keep either one. |
| no branch on remote | The remote has no branch with your branch's name. ([unchanged](test/scenarios/feature-branch-unchanged/README.md), [changed](test/scenarios/feature-branch-changed/README.md)) | Run `git subtrees push`. It creates the branch only if the subtree changed (see *Pushing a new branch*). |

More scenarios:

- [`init-copied-content`](test/scenarios/init-copied-content/README.md):
  `init` on a folder copied in by hand with exactly the remote's content.
- [`init-on-feature-branch`](test/scenarios/init-on-feature-branch/README.md):
  `init` on a branch the remote doesn't have yet.
- [`init-unrelated-content`](test/scenarios/init-unrelated-content/README.md):
  `init` on a folder whose content has nothing to do with the remote.
- [`nested-subtrees`](test/scenarios/nested-subtrees/README.md): why one
  subtree inside another is refused.
- [`shared-remote-url`](test/scenarios/shared-remote-url/README.md): two
  subtrees with the same remote URL act like two clones of one repo.

[How the last sync point is found](docs/last-synced-commit/README.md)
explains how the states are worked out and lists known limitations.

## Installation

With [Nix](https://nixos.org/download/), which brings its own Bash, Git and
shell completions:

    nix profile install github:roschaefer/git-subtrees
    nix run github:roschaefer/git-subtrees -- status   # or try it first

Otherwise, clone it:

    git clone https://github.com/roschaefer/git-subtrees.git
    mkdir -p ~/.local/bin
    ln -s "$(pwd)/git-subtrees/git-subtrees" ~/.local/bin/git-subtrees

Git runs any `git-<name>` executable on your `PATH` as `git <name>`, so make
sure `~/.local/bin` is on it. Symlink only the `git-subtrees` file. The
`lib/` folder must stay next to it.

Requires:

- Bash >= 4.4. macOS ships 3.2, so install a newer one (e.g.
  `brew install bash`) and put it first on your `PATH`.
- `git subtree`, which most Linux distributions bundle with git. Check with
  `git subtree --help`.

### Shell completions

`completions/` has completions for bash, zsh and fish. They complete
subcommands and subtree paths. The Nix package installs them; for a clone:

    # bash: source from ~/.bashrc
    source /path/to/git-subtrees/completions/git-subtrees.bash

    # zsh: install as `_git-subtrees` on your $fpath, then restart the shell
    ln -s /path/to/git-subtrees/completions/git-subtrees.zsh \
      /usr/local/share/zsh/site-functions/_git-subtrees

    # fish
    ln -s /path/to/git-subtrees/completions/git-subtrees.fish \
      ~/.config/fish/completions/git-subtrees.fish

## Development

With [Nix](https://nixos.org/download/) and
[flakes](https://wiki.nixos.org/wiki/Flakes), run in the clone:

    nix develop      # shell with the dev tools and this checkout on PATH
    just --list      # lint, fmt, test, ci, bench, walkthrough, ...
    just walkthrough # try commands by hand in a throwaway monorepo

Scenario fixtures for the tests are in `test/scenarios/`, each with a
README. Pull requests out of draft get a benchmark against their base in
the job summary of the Benchmark workflow.

Releases come from [release-please](https://github.com/googleapis/release-please):
it keeps a release PR open with the next version and changelog, built from
the Conventional Commits on `main`. Merging it tags and publishes the
release.

## License

MIT, see [LICENSE](LICENSE).
