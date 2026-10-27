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

## The output is real

No output in these docs is pasted in.
[scrut](https://facebookincubator.github.io/scrut/) runs every command
on these pages and compares what it prints. To get the same output on
every run, it runs them in the C locale and GMT, and each page starts
with a setup block, which GitHub doesn't render, that fixes the commit
dates and author and keeps your git config out.

Every page is tested in CI, so the docs are the specification of
`git-splice`, written as examples: what each command prints in each
scenario. This is [specification by
example](https://en.wikipedia.org/wiki/Specification_by_example).
`just docs-check` runs them all, and `just docs-check --write` updates
the pages after an intended change.
