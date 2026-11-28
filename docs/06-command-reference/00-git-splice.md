# git-splice

`git-splice` keeps folders of a monorepo in sync with their own upstream
repositories. See the [walkthrough](../01-getting-started/02-walkthrough.md)
for a first workflow, and the individual command pages for their options
and examples.

## Usage

    git splice <command> [<args>]

`git splice` and `git splice --help` open an offline general usage manual
with command descriptions and examples. `git splice -h` prints a brief
command overview.
Use `git splice <command> -h` for detailed help for a particular command.

## Manual installation

The Nix package installs the manual. With a release archive or a source
checkout, install it into a directory your `man` searches, for example:

    mkdir -p ~/.local/share/man/man1
    install -m644 man/git-splice.1 ~/.local/share/man/man1/git-splice.1

`cargo install` installs the executable only; install the manual from a
matching source checkout separately. Viewing the manual requires `man`;
`git splice -h` and command-specific `-h` work without it.

