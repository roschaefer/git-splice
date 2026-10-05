# git-splice

Keep folders of your monorepo in sync with their own repositories, in both
directions: to publish a package, mirror a library, or keep a vendored copy
up to date. Switch branches in the monorepo, and every folder switches the
branch it syncs with.

## The problem

You vendored a library into your monorepo and fixed a bug in it, tested
together with your app. Now the fix should go back to the library's own
repository, but it is buried in monorepo commits that also touch `app/`,
and the two repositories share no history:

```text
  your monorepo                              github.com/x/lib
 ┌──────────────────────────────┐           ┌─────────────────────┐
 │ app/                         │           │ src/                │
 │ vendor/lib/  (copy of x/lib) │           │ README.md           │
 │   src/       ← your fix      │ ───?───▶  │                     │
 └──────────────────────────────┘           └─────────────────────┘
   one history for app and lib                its own history
```

The same holds the other way round: a package developed in the monorepo
that you publish as its own repository, while still merging outside
contributions back in. Neither side should become the source of truth.

## The solution

Instead of copying the library, splice it in once:

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/test/readme/scrut-setup.sh"
```
-->

```scrut
$ git splice clone https://github.com/x/lib.git vendor/lib
===  vendor/lib: fetching https://github.com/x/lib.git
ok   vendor/lib: cloned e849115 from main
```

(If `vendor/lib` already holds a changed copy, `clone --merge` keeps both,
and every file that differs becomes a conflict to resolve.)

From then on, `git splice pull vendor/lib` brings upstream changes in as
one ordinary monorepo commit, and `git splice push vendor/lib` rebuilds the
monorepo commits that touched `vendor/lib/` as commits of the library,
containing only that folder. Both histories are shown as
`git log --graph --oneline` shows them, newest first:

```text
  monorepo                                    github.com/x/lib

  * (HEAD -> fix-parser) app: call parse()
  * fix parse() options          ── push ──▶  * (fix-parser) fix parse() options
  * rename helper in app and lib ── push ──▶  * rename helper in app and lib
  |                                           |
  * (main) splice: clone          ◀── clone ── * (main) e849115 release 1.2
  |   vendor/lib from main at e849115
  * app: initial commit
```

Point the URL at your fork, and the pushed branch is ready for a pull
request. Changes cross the boundary, but commits don't: both repositories
keep their own histories.

The splice's state is one committed file:

```scrut
$ cat vendor/lib/.splice
[splice]
	url = https://github.com/x/lib.git
	commit = e8491155fe5db4e87fd6c1227ab65fd61da8af0a
```

`commit` is the sync point: the upstream commit the folder last matched.
Everything else follows from two rules:

1. **The folder carries its own state.** Move it with `git mv`, and the
   splice moves along. Push unpushed commits first: a push after the move
   squashes them into it
   ([#4](test/scenarios/moved-with-unpushed-commits/README.md)). A clone of the monorepo has every splice, with no
   setup.
2. **Your local branch name is the upstream branch name.** On `feature-x`,
   every splice syncs with its upstream's `feature-x`. On the monorepo's
   default branch, it syncs with the upstream's default branch, whatever
   its name ([example](test/scenarios/default-branch/README.md)).

[The design](docs/design/README.md) explains the model, how it
[compares](docs/design/README.md#how-it-compares) to `git submodule`,
`git subtree`, git-subrepo, Josh, Copybara and others, and its
[limits](docs/design/README.md#limits).

## Example

[A walkthrough of every command](test/walkthrough/README.md) shows what each one
prints, on a throwaway monorepo whose upstreams live on the same machine.
To follow along, run `just walkthrough` in a clone of this repository.

## Commands

`merge`, `pull` and `push` change the monorepo or an upstream, so they name
their splices, or take `--all`. `clone` and `init` start one splice each.
Commands that only look cover every splice unless you name some. Run `git splice <command> --help` for options.

| Command | What it does |
| --- | --- |
| `clone <url> [<path>]` | Splices an existing repository into a new folder, as one commit. Use `--merge` if the folder already exists and differs. |
| `init <path> <url>` | Makes a folder a splice of a new, empty repository. The first `push` publishes its history. |
| `merge <path>…` | Splices already-fetched upstream changes in, as one ordinary commit per splice. |
| `pull <path>…` | `fetch` + `merge`. |
| `push <path>…` | Rebuilds the commits that changed each splice since the last sync and pushes them upstream. Writes nothing to the monorepo. |
| `status [path…]` | Shows each splice's [sync state](#sync-states). |
| `diff [path…]` | Shows the file changes `push` would send. |
| `log [path…]` | Shows the commits `push` would publish and `pull` would bring in, with their authors. |
| `fetch [path…]` | Fetches every branch of each upstream into `refs/splices/<path>/`. |

`status`, `diff`, `log` and `merge` only use what was last fetched. Run
`git splice fetch` first if you need the latest upstream state. Fetched
upstreams can be read with any Git command, e.g.
`git log splices/vendor/lib/main`.

Upstreams are fetched and pushed by URL, with no Git remote, so a plain
`git push` can't send the whole monorepo to one by mistake
([more](docs/design/README.md#refs-instead-of-remotes)). A `push` creates a
new upstream branch only if the splice changed on your branch
([more](docs/design/README.md#splicing-out-push-and-the-rebuild)).

## Sync states

`status` reports one of these states for each splice, and `merge`, `pull`
and `push` act on it. Each example is a small, tested scenario;
[all scenarios](test/scenarios/README.md) cover more situations.

| State | Meaning | What to do |
| --- | --- | --- |
| never fetched | The upstream wasn't fetched in this clone yet. ([example](test/scenarios/never-fetched/README.md)) | Run `git splice fetch`. |
| up to date | Both sides are the same. ([example](test/scenarios/up-to-date/README.md)) | Nothing to do. |
| push | Only your side changed. ([example](test/scenarios/push-ahead/README.md)) | Run `git splice push`. |
| pull | Only the upstream changed. ([example](test/scenarios/pull-ahead/README.md)) | Run `git splice pull`. |
| diverged | Both sides changed since they last matched. ([example](test/scenarios/diverged-common-ancestor/README.md)) | Run `git splice pull`, then `push`. On a conflict, resolve it and `git commit` first. |
| unrelated history | Both sides changed and share no history, e.g. the upstream was rebuilt from scratch. ([example](test/scenarios/diverged-unrelated-history/README.md)) | Pick a side. `merge`, `pull` and `push` refuse to guess and print the commands to keep either side, or both. |
| upstream has no such branch | The upstream has no branch with your branch's name. ([unchanged](test/scenarios/feature-branch-unchanged/README.md), [changed](test/scenarios/feature-branch-changed/README.md)) | Run `git splice push`. It creates the branch only if the splice changed. |

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

## Documentation

The [documentation site](https://roschaefer.github.io/git-splice/) has
this README, the
[walkthrough](https://roschaefer.github.io/git-splice/test/walkthrough/),
[all scenarios](https://roschaefer.github.io/git-splice/test/scenarios/),
the [comparisons](https://roschaefer.github.io/git-splice/test/comparisons/)
and [the design](https://roschaefer.github.io/git-splice/docs/design/) in
one place.

## Development

With [Nix](https://nixos.org/download/) and
[flakes](https://wiki.nixos.org/wiki/Flakes), run in the clone:

    nix develop      # shell with the dev tools and this checkout on PATH
    just --list      # lint, fmt, test, ci, bench, walkthrough, ...
    just walkthrough # try commands by hand in a throwaway monorepo

[The design](docs/design/README.md#testing) explains how the tests are
layered and how to write one.

Releases come from [release-please](https://github.com/googleapis/release-please):
it keeps a release PR open with the next version and changelog, built from
the Conventional Commits on `main`. Merging it tags and publishes the
release.

## License

MIT, see [LICENSE](LICENSE).
