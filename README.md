# git-subtrees

Keep several `git subtree` folders of a monorepo in sync with their own
repositories: publish a package, mirror a library, or keep a vendored copy
up to date. You don't need a config file.

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
subcommands and subtree paths.

    # bash: source from ~/.bashrc (git's dispatch to _git_subtrees needs
    # the function defined up front, so lazy loading doesn't work)
    source /path/to/git-subtrees/completions/git-subtrees.bash

    # zsh: install as `_git-subtrees` on your $fpath, then restart the shell
    ln -s /path/to/git-subtrees/completions/git-subtrees.zsh \
      /usr/local/share/zsh/site-functions/_git-subtrees

    # fish
    ln -s /path/to/git-subtrees/completions/git-subtrees.fish \
      ~/.config/fish/completions/git-subtrees.fish

## Development

You need:

- [Nix](https://nixos.org/download/) with
  [flakes enabled](https://wiki.nixos.org/wiki/Flakes)
- a clone of this repository

Then, in the clone,

    nix develop

opens a shell with all development tools and the live `git-subtrees` on
`PATH`.

    just lint       # shellcheck
    just fmt-check  # shfmt -d
    just fmt        # shfmt -w
    just test       # bats --recursive test
    just ci         # lint + fmt-check + test, same as CI
    just bench      # time status/diff/fetch on a synthetic monorepo

`just bench --compare <other checkout>/git-subtrees` times another version
side by side, e.g. a worktree of `main`; see `bench/run.sh --help`. Pull
requests get the same comparison against their base in the job summary of
the Benchmark workflow once they're out of draft.

Tests are in `test/`. Scenario fixtures are in `test/scenarios/`, one
folder per scenario with a README that explains it.

    playground/setup.sh

builds a throwaway monorepo with test remotes for trying things by hand.
Run it inside `nix develop`. Pass `--no-shell` to print the sandbox path
instead of opening a shell there.

    simulate-remote-change <path> [message]

also on `PATH` inside `nix develop`, pushes one new commit to a remote so
you can try `pull` again.

## License

MIT, see [LICENSE](LICENSE).
