# Try it in a sandbox

To try git-splice without touching your own repositories, run this in a
clone of git-splice:

    nix develop       # a shell with the dev tools and this checkout on PATH
    just walkthrough

Without Nix, [install](installation.md) `git splice` first, then run
`test/walkthrough/setup.sh` in the clone.

It builds a throwaway monorepo in a temporary directory and opens a shell
in it. The [walkthrough](../test/walkthrough/README.md) shows what to
type there. Each of its pages starts from a fresh sandbox, and CI runs
them with [scrut](https://facebookincubator.github.io/scrut/), so the
output they show is what the current version prints.

What you get:

- `$WALKTHROUGH/monorepo`: the monorepo, on `main`. You start here.
- `$WALKTHROUGH/upstream/pkg-a.git`, `pkg-b.git` and `lib-c.git`: bare
  repositories on the same machine that stand in for the splices'
  upstreams. The monorepo reaches them as
  `https://git.example.com/<name>.git`: its `url.<base>.insteadOf` maps
  that prefix to `$WALKTHROUGH/upstream/`. The sandbox's shell exports
  `$WALKTHROUGH`, so you can paste the walkthrough's commands as they
  are.
- `vendor/pkg-a`: a splice whose upstream has one commit the monorepo
  doesn't have yet. It's already fetched.
- `pkg-b.git`: a repository that isn't spliced in yet.
- `libs/c`: a folder of the monorepo, to be published to the empty
  `lib-c.git`.

To push a commit to an upstream as if someone else had, clone it next to
the monorepo, commit there and push, as in the walkthrough's
[fetch](../test/walkthrough/README.md#fetch). The sandbox's shell names
you "Walkthrough" for such commits, and otherwise uses your git config.
