# VCS compatibility

These scenarios reproduce the limits described in the
[Sapling](../../05-comparisons/03-vcs/01-sapling.md) and
[Jujutsu](../../05-comparisons/03-vcs/02-jj.md) comparisons:

- [Sapling sync metadata after a Git squash](01-sapling-metadata/README.md).
- [Sapling's Git index and branch state](02-sapling-git-index/README.md).
- [Jujutsu and the named Git branch](03-jujutsu-named-branch/README.md).

They use the versions pinned in [`flake.nix`](../../../flake.nix). The
Sapling scenarios run on Linux, where the development shell packages it.
Their exact output establishes behavior for those versions.

## Shared setup

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds a library with one commit, an app
monorepo, and a second monorepo with the library already spliced in:

```scrut
$ build_scenario scenario_vcs_compatibility
```

```scrut
$ git -C ../splice-monorepo splice status
On branch main

  up to date  vendor/lib
```
