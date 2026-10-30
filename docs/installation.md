# Installation

With [Nix](https://nixos.org/download/) and
[flakes](https://wiki.nixos.org/wiki/Flakes) enabled, which brings its own
Git and shell completions:

    nix profile install github:roschaefer/git-splice
    nix run github:roschaefer/git-splice -- status   # or try it first

Otherwise, download a binary for Linux or macOS, x86-64 or ARM, from the
[releases](https://github.com/roschaefer/git-splice/releases), and put
`git-splice` on your `PATH`. The tarball also has the shell completions.

Or build it with [Rust](https://rustup.rs):

    cargo install --git https://github.com/roschaefer/git-splice

Git runs any `git-<name>` executable on your `PATH` as `git <name>`, so make
sure `~/.cargo/bin/` is on it.

Requires:

- Git >= 2.40. `git subtree` isn't needed.

## Shell completions

`completions/` has completions for bash, zsh and fish. They complete
commands, splice paths and `--rebuilt-commit` branches. The Nix package installs
them; for a clone:

    # bash: source from ~/.bashrc
    source /path/to/git-splice/completions/git-splice.bash

    # zsh: install as `_git-splice` on your $fpath, then restart the shell
    ln -s /path/to/git-splice/completions/git-splice.zsh \
      /usr/local/share/zsh/site-functions/_git-splice

    # fish
    mkdir -p ~/.config/fish/completions
    ln -s /path/to/git-splice/completions/git-splice.fish \
      ~/.config/fish/completions/git-splice.fish

## Try it first

A clone of `git-splice` can also build a throwaway monorepo and open a
shell in it, to try the commands without touching your own repositories:
see [the sandbox](sandbox.md).
