# Try it in a sandbox

To try `git-splice` without touching your own repositories, run this in a
clone of `git-splice`:

    nix develop       # a shell with the dev tools and this checkout on PATH
    just walkthrough

Without Nix, [install](installation.md) `git-splice` first, then run
`test/walkthrough/setup.sh` in the clone.

It builds a throwaway monorepo in a temporary directory and opens a shell
in it. The [walkthrough](../test/walkthrough/README.md) shows what to
type there, and each of its pages starts from a fresh sandbox.

What you get:

- `$WALKTHROUGH/monorepo`: the monorepo, on `main`. You start here.
- `$WALKTHROUGH/upstream/pkg-a.git`, `pkg-b.git` and `lib-c.git`: bare
  repositories on the same machine that stand in for the splices'
  upstreams. The monorepo reaches them as
  `https://git.example.com/<name>.git`: its `url.<base>.insteadOf` maps
  that prefix to `$WALKTHROUGH/upstream/`. The sandbox's shell exports
  `$WALKTHROUGH`, so you can paste the walkthrough's commands as they
  are.
- `vendor/pkg-a/`: a splice whose upstream has one commit the monorepo
  doesn't have yet. It's already fetched.
- `pkg-b.git`: a repository that isn't spliced in yet.
- `libs/c/`: a folder of the monorepo, to be published to the empty
  `lib-c.git`.

To push a commit to an upstream as if someone else had, clone it next to
the monorepo, commit there and push, as in the walkthrough's
[fetch](../test/walkthrough/README.md#fetch). The sandbox's shell names
you "Walkthrough" for such commits, and otherwise uses your git config.

## Any page, in a sandbox

Each page of these docs that runs commands, a walkthrough chapter, a
concept, a scenario or a comparison, has a sandbox of its own, in the
state the page starts from. In a clone of `git-splice`:

    nix develop
    just sandbox comparisons/git-submodule

The page is its path under `test/`, with or without `.md`: e.g.
`scenarios/02-starting-a-splice/01-clone-copied-content` for that
scenario's README. Without Nix, run `test/sandbox.sh` with the page; it
needs Bash and Git, and the tool a page compares with, e.g. `git-subrepo`.
Without a page, it lists them.

The sandbox runs the page's commands up to the first one that prints
something, so it has the page's setup, and drops you into a shell in its
monorepo. The shell has the page's environment: its commit dates, its
author and its URLs, which lead from `https://git.example.com/` to the
repositories next door. Your own git config stays out, as it does for the
page. So the page's commands, pasted as they are, print what the page
shows, commit hashes included.

## The output is real

No output in these docs is pasted in.
[scrut](https://facebookincubator.github.io/scrut/) runs every command
on the walkthrough, concept, scenario and comparison pages and compares
what it prints, so the output is what the current version prints.
`just docs-check` runs them all, in CI too, and
`just docs-check --write` updates the pages after an intended change.

Each page starts with a block that GitHub doesn't render. It sources a
setup script, here [`scrut-setup.sh`](../test/walkthrough/scrut-setup.sh),
which builds the repositories, fixes the commit dates and ignores your
git config, so commit hashes are the same on every run.
