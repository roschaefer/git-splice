# Starting a splice

Making a folder a splice: with `clone`, with `init`, or from a submodule.

- [clone-copied-content](01-clone-copied-content/README.md): a folder
  copied in by hand, with exactly the upstream's content.
- [clone-differing-content](02-clone-differing-content/README.md): a
  folder maintained by hand, with other content than the upstream.
- [clone-on-feature-branch](03-clone-on-feature-branch/README.md):
  cloning while on a branch the upstream doesn't have.
- [init-new-upstream](04-init-new-upstream/README.md): a folder that grew
  in the monorepo, published to a new, empty repository.
- [init-then-cloned](05-init-then-cloned/README.md): a colleague clones
  a monorepo with a splice made by `init`. A known bug.
- [clone-without-commits](06-clone-without-commits/README.md): cloning
  into a brand-new monorepo without commits.
- [submodule-in-linked-worktree](07-submodule-in-linked-worktree/README.md):
  a submodule checked out in the monorepo and in a linked worktree.
- [clone-from-submodule](08-clone-from-submodule/README.md): a submodule
  turned into a splice.
- [clone-under-monorepo-attributes](09-clone-under-monorepo-attributes/README.md):
  the monorepo's `.gitattributes` sets line endings the upstream
  doesn't.
