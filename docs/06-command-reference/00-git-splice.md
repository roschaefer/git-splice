# git-splice

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../tests/walkthrough/scrut-setup.sh" &&
>   mkdir man &&
>   cp "$TESTDIR/../../man/git-splice.1" man/ &&
>   man_dir="$PWD/share/man"
```
-->

`git-splice` keeps folders of a monorepo in sync with their own upstream
repositories. See the [walkthrough](../01-getting-started/02-walkthrough.md)
for a first workflow, and the individual command pages for their options
and examples.

## Usage

```scrut
$ git splice -h
usage: git splice <command> [<args>]

A splice is a folder of this repository that has its own upstream
repository, recorded in <path>/.splice. Every splice syncs with the
upstream branch named like the current branch.

Splicing in or out -- name the splices, or pass --all:
  clone [--merge] <url> [<path>]      splice an existing repository in
  clone --from-submodule [--recursive] <path>
                                      turn a submodule into a splice
  init <path> <url>                   make a folder a splice of an empty repository
  merge [--upstream <n>] (<path>... | --all)
                                      splice in already-fetched upstream changes
  pull [--upstream <n>] (<path>... | --all)
                                      fetch, then merge
  push [--upstream <n>] [--force] (<path>... | --all)
                                      publish local changes upstream

Looking -- every splice unless paths are given:
  status [--upstream <n>] [path...]   show each splice's sync state
  diff [--upstream <n>] [--stat] [path...]
                                      show the file changes push would send
  log [--upstream <n>] [--graph] [path...]
                                      show the commits push and pull would move
  fetch [--upstream <n>] [path...]    fetch the upstreams

New to git splice -- one splice each:
  boundary <path>                     print the commit the rebuild of a splice starts from
  rebuild <path>                      print the commit push would send
  key [--upstream <name>] <path> [<new-key>]
                                      print or rename the key of a splice's fetched refs

--upstream names one of a splice's upstreams in .splice; without it, the
splice's default upstream.

Run 'git splice <command> -h' for command-specific help, and
'git splice --version' for the version.
```

`git splice` and `git splice --help` open an offline general usage manual
with command descriptions and examples. `git splice -h` prints a brief
command overview.
Use `git splice <command> -h` for detailed help for a particular command.

## Manual installation

The Nix package installs the manual. With a release archive or a source
checkout, choose a directory your `man` searches, such as
`~/.local/share/man`, as `$man_dir`, then install the manual:

```scrut
$ mkdir -p "$man_dir/man1" &&
>   install -m644 man/git-splice.1 "$man_dir/man1/git-splice.1"
```

`cargo install` installs the executable only; install the manual from a
matching source checkout separately. Viewing the manual requires `man`;
`git splice -h` and command-specific `-h` work without it.

<!-- Check the installed manual through Git, including the default invocation.
```scrut
$ export MANPATH="$man_dir:" MANPAGER=cat &&
>   git -c help.format=man splice --help >explicit-help.txt &&
>   git -c help.format=man splice >default-help.txt &&
>   man git-splice >manual.txt &&
>   cmp manual.txt explicit-help.txt &&
>   cmp explicit-help.txt default-help.txt &&
>   grep -q '^EXAMPLES$' manual.txt
```
-->
