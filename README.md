# git-splice

Keep folders of your monorepo in sync with their own repositories, in both
directions: to publish a package, mirror a library, or keep a vendored copy
up to date. Switch branches in the monorepo, and every folder switches the
branch it syncs with.

## The problem

Some folders belong in a monorepo for development and testing, but also need
their own repositories. You may want to publish one without publishing the
whole monorepo, while still merging dependency updates and outside
contributions back in.

Or you vendor a library to develop and test a patch with your application.
Contributing the patch back means getting those changes into a fork of the
library, whose history is separate from the monorepo's.

Both cases need changes to cross between a monorepo folder and a standalone
repository in either direction, without making either one the source of truth.

## The solution

A **splice** is an ordinary folder in the monorepo with a committed `.splice`
file. Like a subtree, its files live directly in the monorepo, where they can
be changed and tested with everything else. Like a submodule, the monorepo
records an upstream repository and one of its commits.

The commit has a different meaning than a submodule's gitlink. A submodule
commit says which revision should be checked out. A splice commit is a sync
point: the upstream revision the folder matched when changes were last spliced
in. It does not determine the folder's current content; later monorepo commits
can change it, and a push does not update the sync point.

From that point, `git-splice` lets Git merge upstream changes and resolve
conflicts, or rebuild the folder's monorepo commits for a push. Changes cross
the boundary, but commits do not: both repositories keep their own histories.

Create a splice with:

    git splice clone https://github.com/x/lib.git vendor/lib

```
$ cat vendor/lib/.splice
[splice]
	url = https://github.com/x/lib.git
	commit = 3f1c…
```

`url` identifies the upstream repository. `commit` is its sync point;
`clone`, `merge` and `pull` update it, but `push` does not.
Everything follows from two rules:

1. **The folder carries its own state.** Move it with `git mv`, and the
   splice moves along. A clone of the monorepo has every splice, with no
   setup.
2. **Your local branch name is the upstream branch name.** On `feature-x`,
   every splice syncs with its upstream's `feature-x`. On the monorepo's
   default branch, it syncs with the upstream's default branch, whatever
   its name ([example](test/scenarios/default-branch/README.md)).

Splices can't be nested
([why](test/scenarios/nested-splices/README.md)), so an upstream that
contains a `.splice` of its own can't be cloned or merged. A splice's path
must also work in a Git ref name, so no spaces.

## How it compares

`git-splice` grew out of
[git-subtrees](https://github.com/roschaefer/git-subtrees), a layer on `git
subtree`. [The design](docs/design/README.md) explains why it was rewritten.

| Tool | What is similar | Key difference |
| --- | --- | --- |
| `git submodule` | The monorepo commits an upstream URL and commit. | A submodule commit selects the revision in a separate worktree. A splice commit only marks an earlier sync point; the folder is ordinary monorepo content and may have changed since. |
| `git subtree` | The files live in the monorepo and are developed there. | A subtree has no state file. Pulling imports upstream history or a squash commit and merge; a splice records its sync point and pulls as one ordinary monorepo commit. |
| [git-subrepo](https://github.com/ingydotnet/git-subrepo) | It has a committed state file, fetches by URL and pulls as one commit. | It stores a monorepo commit that rebases and squash merges can invalidate, and fixes each folder to one branch. |
| [splitsh-lite](https://github.com/splitsh/lite) | It publishes folders as repositories. | It creates read-only mirrors; changes only flow out. |
| [Josh](https://github.com/josh-project/josh) | It exposes part of a monorepo as a repository. | The monorepo remains authoritative, and contributors work through filtered views of it. |
| [Copybara](https://github.com/google/copybara) | It moves changes between repositories. | One repository is the source of truth; syncing back needs a separate reverse workflow. |

## Example

[A walkthrough of every command](walkthrough/README.md) shows what each one
prints, on a throwaway monorepo whose upstreams live on the same machine.
To follow along, run `just walkthrough` in a clone of this repository.

## Commands

Commands that splice in or out change the monorepo or an upstream, so they
name their splices, or take `--all`. Commands that only look cover every
splice unless you name some. Run `git splice <command> --help` for options.

| Command | What it does |
| --- | --- |
| `clone <url> [<path>]` | Splices an existing repository into a new folder, as one commit. |
| `init <path> <url>` | Makes a folder a splice of a new, empty repository. The first `push` publishes its history. |
| `merge <path>…` | Splices already-fetched upstream changes in, as one ordinary commit per splice. |
| `pull <path>…` | `fetch` + `merge`. |
| `push <path>…` | Rebuilds the commits that changed each splice since the last sync and pushes them upstream. Writes nothing to the monorepo. |
| `status [path…]` | Shows each splice's [sync state](#sync-states). |
| `diff [path…]` | Shows the file changes `push` would send. |
| `log [path…]` | Shows the commits `push` would publish and `pull` would bring in, with their authors. |
| `fetch [path…]` | Fetches every branch of each upstream into `refs/splices/<path>/`. |

`status`, `diff`, `log` and `merge` only use what was last fetched. Run
`git splice fetch` first if you need the latest upstream state.

**No Git remotes.** Upstreams are fetched and pushed by URL, so nothing can
send the whole monorepo to one by mistake, not even a plain `git push` with
`push.autoSetupRemote`. `url.<base>.insteadOf` and `pushInsteadOf` apply as
usual.

**Looking at an upstream.** `fetch` keeps each upstream's complete history
in the monorepo, so every Git command can read it as of the last fetch, as
`splices/<path>/<branch>`. Nothing needs to be cloned:

    git log --oneline splices/vendor/lib/main
    git show splices/vendor/lib/main:README.md
    git worktree add --detach ../lib-upstream splices/vendor/lib/main

`git log --all` and `gitk --all` show those histories too; add
`--exclude='refs/splices/*'` before `--all` to leave them out.

**One commit per pull.** A pull is an ordinary commit that changes the
splice and its `.splice`; upstream's history stays upstream. A conflict
stops it like any merge: resolve it and run `git commit`.

**Pushing a new branch.** If a splice's upstream doesn't have your branch
yet, `push` creates it only when that splice changed on your branch. So
starting a feature branch doesn't create empty branches on every upstream.
"Changed" is measured against the monorepo's base branch: `--base <branch>`
if you pass it, else the monorepo's default branch (`origin/HEAD`, else
`init.defaultBranch`). If none of these work, `push` asks for `--base`
instead of guessing.

**Starting a splice.**

| Situation | Command |
| --- | --- |
| The upstream exists, the folder doesn't | `git splice clone <url> [<path>]` |
| The folder exists, the upstream is new and empty | `git splice init <path> <url>` |
| Both exist with the same content | `git splice clone <url> <path>` only adds `.splice` |
| Both exist and differ | `git splice clone --merge <url> <path>`: every file that differs becomes a conflict, nothing is lost |

The monorepo needs at least one commit: a clone is a commit on top of it.

## Sync states

`status` reports one of these states for each splice, and `merge`, `pull`
and `push` act on it. Each linked scenario is a small, tested example of
that state.

| State | Meaning | What to do |
| --- | --- | --- |
| never fetched | The upstream wasn't fetched in this clone yet. ([example](test/scenarios/never-fetched/README.md)) | Run `git splice fetch`. |
| up to date | Both sides are the same. ([example](test/scenarios/up-to-date/README.md)) | Nothing to do. |
| push | Only your side changed. ([example](test/scenarios/push-ahead/README.md)) | Run `git splice push`. |
| pull | Only the upstream changed. ([example](test/scenarios/pull-ahead/README.md)) | Run `git splice pull`. |
| diverged | Both sides changed since they last matched. ([example](test/scenarios/diverged-common-ancestor/README.md)) | Run `git splice pull`, then `push`. On a conflict, resolve it and `git commit` first. |
| unrelated history | Both sides changed and share no history, e.g. the upstream was rebuilt from scratch. ([example](test/scenarios/diverged-unrelated-history/README.md)) | Pick a side. `merge`, `pull` and `push` refuse to guess and print the commands to keep either side, or both. |
| upstream has no such branch | The upstream has no branch with your branch's name. ([unchanged](test/scenarios/feature-branch-unchanged/README.md), [changed](test/scenarios/feature-branch-changed/README.md)) | Run `git splice push`. It creates the branch only if the splice changed (see *Pushing a new branch*). |

More scenarios:

- [`pushed-then-changed`](test/scenarios/pushed-then-changed/README.md):
  a push, then more local changes. The next push fast-forwards.
- [`diverged-then-pulled`](test/scenarios/diverged-then-pulled/README.md):
  a pull merged a divergence; the local commit still reaches upstream as
  its own commit.
- [`squash-merged-pull`](test/scenarios/squash-merged-pull/README.md):
  a pull on a branch that was squash-merged.
- [`merge-in-monorepo`](test/scenarios/merge-in-monorepo/README.md): unlike
  `git subtree`, merges in the monorepo become ordinary upstream commits;
  [repeated merges](test/scenarios/merge-in-monorepo/multiple-main-merges.md)
  behave the same way.
- [`copybara-contributor-workflow`](test/scenarios/copybara-contributor-workflow/README.md):
  test an external contribution in the monorepo while keeping its merge in
  the public upstream repository.
- [`clone-copied-content`](test/scenarios/clone-copied-content/README.md),
  [`clone-differing-content`](test/scenarios/clone-differing-content/README.md),
  [`clone-on-feature-branch`](test/scenarios/clone-on-feature-branch/README.md),
  [`clone-without-commits`](test/scenarios/clone-without-commits/README.md),
  and [invalid paths](test/scenarios/clone-without-commits/ref-friendly-path.md):
  `clone` where something is there already, or missing.
- [`init-new-upstream`](test/scenarios/init-new-upstream/README.md):
  publishing a folder that grew in the monorepo.
- [`shared-remote-url`](test/scenarios/shared-remote-url/README.md): two
  splices with the same upstream URL act like two clones of one repository.

[The design](docs/design/README.md) explains how states are worked out,
how a push is rebuilt, and where it deliberately differs from `git subtree
split`.

## Installation

With [Nix](https://nixos.org/download/), which brings its own Bash, Git and
shell completions:

    nix profile install github:roschaefer/git-splice
    nix run github:roschaefer/git-splice -- status   # or try it first

Otherwise, clone it:

    git clone https://github.com/roschaefer/git-splice.git
    mkdir -p ~/.local/bin
    ln -s "$(pwd)/git-splice/git-splice" ~/.local/bin/git-splice

Git runs any `git-<name>` executable on your `PATH` as `git <name>`, so make
sure `~/.local/bin` is on it. Symlink only the `git-splice` file. The `lib/`
folder must stay next to it.

Requires:

- Bash >= 4.4. macOS ships 3.2, so install a newer one (e.g.
  `brew install bash`) and put it first on your `PATH`.
- Git >= 2.40. `git subtree` isn't needed.

### Shell completions

`completions/` has completions for bash, zsh and fish. They complete
commands, splice paths and `--base` branches. The Nix package installs
them; for a clone:

    # bash: source from ~/.bashrc
    source /path/to/git-splice/completions/git-splice.bash

    # zsh: install as `_git-splice` on your $fpath, then restart the shell
    ln -s /path/to/git-splice/completions/git-splice.zsh \
      /usr/local/share/zsh/site-functions/_git-splice

    # fish
    ln -s /path/to/git-splice/completions/git-splice.fish \
      ~/.config/fish/completions/git-splice.fish

## Development

With [Nix](https://nixos.org/download/) and
[flakes](https://wiki.nixos.org/wiki/Flakes), run in the clone:

    nix develop      # shell with the dev tools and this checkout on PATH
    just --list      # lint, fmt, test, ci, bench, walkthrough, ...
    just walkthrough # try commands by hand in a throwaway monorepo

Scenario fixtures for the tests are in
[`test/scenarios/`](test/scenarios/README.md), each with a README that
shows the tool's output in that state, checked like the walkthroughs by
`just docs-check`. The push rebuild is tested against `git subtree split`
as an oracle (`test/rebuild.bats`). Pull requests out of draft get a
benchmark against their base in the job summary of the Benchmark workflow.

Releases come from [release-please](https://github.com/googleapis/release-please):
it keeps a release PR open with the next version and changelog, built from
the Conventional Commits on `main`. Merging it tags and publishes the
release.

## License

MIT, see [LICENSE](LICENSE).
