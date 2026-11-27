# Installation

With [Nix](https://nixos.org/download/) and
[flakes](https://wiki.nixos.org/wiki/Flakes) enabled, which brings the shell
completions and manual:

    nix profile install github:roschaefer/git-splice
    nix run github:roschaefer/git-splice -- status   # or try it first

Otherwise, download a binary for Linux or macOS, x86-64 or ARM, or for
Windows, x86-64, from the
[releases](https://github.com/roschaefer/git-splice/releases), and put
`git-splice` (`git-splice.exe` on Windows) on your `PATH`. The archive also
has the shell completions and `man/git-splice.1`.

Or build it with [Rust](https://rustup.rs):

    cargo install --git https://github.com/roschaefer/git-splice git-splice

Git runs any `git-<name>` executable on your `PATH` as `git <name>`, so make
sure `~/.cargo/bin/` is on it.

Requires:

- Git >= 2.40. `git subtree` isn't needed.

See [known bugs and limitations](../09-scenarios/99-known-bugs.md).

## Help

`git splice -h` prints a brief command overview. `git splice --help` opens
an offline general usage manual with command descriptions and examples.
Use `git splice <command> -h` for detailed help for a particular command.

The Nix package installs the manual. With a release archive or a source
checkout, install it into a directory your `man` searches, for example:

    mkdir -p ~/.local/share/man/man1
    install -m644 man/git-splice.1 ~/.local/share/man/man1/git-splice.1

`cargo install` installs the executable only; install the manual from a
matching source checkout separately. Viewing the manual requires `man`;
`git splice -h` and command-specific `-h` work without it.

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
see [the sandbox](01-sandbox.md).
