# Installation

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

## Shell completions

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
