# Try it in a sandbox

To try `git-splice` without touching your own repositories, run this in a
clone of `git-splice`:

    nix develop -c just sandbox

It opens a shell in a throwaway monorepo, the one the
[walkthrough](../test/walkthrough/README.md) starts from: run the
walkthrough's commands there, and they print what it shows. Without
Nix, run `test/sandbox.sh`; it needs Bash and Git.

## Any page, in a sandbox

Each page of these docs that runs commands, a walkthrough chapter, a
concept, a scenario or a comparison, opens the same way, in the state
the page starts from:

    nix develop -c just sandbox comparisons/git-submodule

The page is its path under `test/`, with or without `.md`: e.g.
`walkthrough/push`, or `scenarios/02-starting-a-splice/01-clone-copied-content`
for that scenario's README. A comparison needs the tool it compares
with, e.g. `git-subrepo`, which `nix develop` has. An unknown page lists
them all. Each page says what its repositories are.

The sandbox builds the state the page starts from: it runs the page's
setup, up to the first command the page shows you, i.e. what the page
hides before it, and what it shows that only calls a helper of the
setup, like a scenario's `build_scenario`. Then it drops you into bash
in the page's monorepo, so you run every command the page shows
yourself, from the first one.

That bash has your `~/.bashrc`, then the page's environment: its commit
dates, its author, its URLs, which lead from `https://git.example.com/`
to the repositories next door, and the C locale and GMT, as scrut runs
it. It has the setup's helpers too, e.g. `seed_bare_repo` for a commit
someone else pushes. Your own git config stays out, as it does for the
page. So the commands, pasted as they are, print what the page shows,
commit hashes included.

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
