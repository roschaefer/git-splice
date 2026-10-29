# Try it in a sandbox

To try `git-splice` without touching your own repositories, run this in a
clone of `git-splice`:

    nix develop -c just sandbox

It opens a shell in a throwaway monorepo, the one the
[walkthrough](../test/walkthrough/README.md) starts from: run the
walkthrough's commands there, and they print what it shows. Without
Nix, run `test/sandbox.sh`; it needs Bash and Git.

## Any page, in a sandbox

The sandbox builds any page of these docs that runs commands, a
walkthrough chapter, a concept, a scenario or a comparison, by its path
under `test/`:

    nix develop -c just sandbox comparisons/git-submodule

It runs the page's setup, up to the first command the page shows, and
opens bash in the page's monorepo, with the settings scrut runs the page
with. So you get the page's output, down to the commit hashes.

## Specification by example

[scrut](https://facebookincubator.github.io/scrut/) runs every command
on these pages and compares its output. The pages are both the
[specification by example](https://en.wikipedia.org/wiki/Specification_by_example)
and the acceptance tests for `git-splice`.

Each page starts with a hidden setup block. It fixes the commit dates
and author, ignores your Git config, and runs in the C locale and GMT,
so the output stays the same in CI and on your machine.
