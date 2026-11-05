# Upstreams

Which upstream a splice syncs with, and which of its branches or tags.

- [default-branch](01-default-branch/README.md): the upstream's default
  branch is `master`, the monorepo's is `main`.
- [several-upstreams](02-several-upstreams/README.md): a library with two
  upstreams, the original and a fork with a patch of its own.
- [shared-remote-url](03-shared-remote-url/README.md): two splices with
  the same upstream URL.
- [upstream-moved](04-upstream-moved/README.md): the upstream moved to a
  new URL while a commit is unpushed.
- [splice-refs](05-splice-refs/README.md): the refs a splice keeps in the
  monorepo, and what they cost.
- [default-pin](06-default-pin/README.md): the default branch pins a
  release tag instead of following a branch.
- [contributing-through-a-fork](07-contributing-through-a-fork/README.md):
  the fork workflow, step by step.
