# The sandbox

`just walkthrough` builds a throwaway monorepo in a temporary directory and
opens a shell in it. The [walkthrough](README.md) and the pages of each
command run there. CI runs these pages with
[scrut](https://facebookincubator.github.io/scrut/), so the output they
show is what the current version prints (`just docs-check`). Each page
starts from a fresh sandbox.

What you get:

- `$WALKTHROUGH/monorepo`: the monorepo, on `main`. You start here.
- `$WALKTHROUGH/upstream/pkg-a.git`, `pkg-b.git` and `lib-c.git`: bare
  repositories on the same machine that stand in for the splices'
  upstreams. The monorepo reaches them as
  `https://git.example.com/<name>.git`: its `url.<base>.insteadOf` maps
  that prefix to `$WALKTHROUGH/upstream/`. The walkthrough shell exports
  `$WALKTHROUGH`, so you can paste the commands as they are.
- `vendor/pkg-a`: a splice whose upstream has one commit the monorepo
  doesn't have yet. It's already fetched.
- `pkg-b.git`: a repository that isn't spliced in yet.
- `libs/c`: a folder of the monorepo, to be published to the empty
  `lib-c.git`.

To push a commit to an upstream as if someone else had, clone it next to
the monorepo, commit there and push, as in the walkthrough's
[fetch](README.md#fetch).
