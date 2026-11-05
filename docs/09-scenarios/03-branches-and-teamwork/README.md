# Branches and teamwork

Feature branches, merges, and colleagues who work on the same splice.

- [feature-branch-unchanged](01-feature-branch-unchanged/README.md): on a
  branch the upstream doesn't have, without changes to the splice.
- [feature-branch-from-main](02-feature-branch-from-main/README.md): a
  feature branch for an upstream that takes changes only through pull
  requests.
- [squash-merged-pull](03-squash-merged-pull/README.md): a pull on a
  feature branch, squash-merged into `main`.
- [concurrent-pulls](04-concurrent-pulls/README.md): two developers pull
  the same splice, and the second merge conflicts.
- [bisect-into-a-pull](05-bisect-into-a-pull/README.md): `git bisect`
  ends at a pull. Which upstream commit brought the bug?
- [teammate-pulled](06-teammate-pulled/README.md): a teammate's pull
  arrives with `git pull`, before this clone fetched the splice.
- [tracked-branch](07-tracked-branch/README.md): splices that sync with
  another upstream branch than the monorepo's.
- [bumped-on-a-feature-branch](08-bumped-on-a-feature-branch/README.md):
  why not to bump on a feature branch.
