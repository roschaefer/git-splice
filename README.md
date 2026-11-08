# git-splice

`git-splice` is a developer-friendly way to work across repositories from
one monorepo. Edit them as folders, test them together, and sync both ways
with plain Git.

## The problem

Your app depends on a library from another repository. You find a bug in
the library while working on the app, but its code isn't yours to change:
all you get is its releases.

<div align="center">

![Your monorepo with app/, and the library repository with src/: releases come in, but a fix has no way back](docs/images/readme-problem.drawio.svg)

</div>

## The common workaround

A fork lets you send fixes back, but leaves the library outside the
monorepo where you build and test the app.

<div align="center">

![Your monorepo with app/, your fork of the library with the fix, and the original: the fork sends pull requests and takes releases, and the monorepo and the fork are two places to maintain](docs/images/readme-workaround.drawio.svg)

</div>

## The solution

Work on the library as a folder next to the app. One commit can change
both, tested together; each repository keeps its own history, reviews and CI.

<div align="center">

![Your monorepo with app/ and the spliced lib/, your fork of the library and the original: git splice push and pull connect the monorepo and the fork, pull requests and releases connect the fork and the original](docs/images/readme-solution.drawio.svg)

</div>

## Getting started

[Install `git-splice`](docs/01-getting-started/README.md), try the
[sandbox](docs/01-getting-started/01-sandbox.md), or follow the
[walkthrough](docs/01-getting-started/02-walkthrough.md).

Use it for libraries, services, or public folders in a private monorepo.
Existing submodules can become folders with
[`git splice clone --from-submodule`](docs/06-command-reference/01-clone.md).
Only the folder's changes are published; the monorepo's history stays separate.

## How it works

Splice your fork of the library in once:

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/docs/readme/scrut-setup.sh"
```
-->

```scrut
$ git splice clone 'https://github.com/<you>/lib.git' lib
===  lib: fetching https://github.com/<you>/lib.git
ok   lib: cloned e849115 from main
```

The folder's committed [`.splice` file](docs/03-concepts/README.md)
records its upstream and last synced commit. Both sides can now change:

<!--
```scrut
$ source "$TESTDIR/docs/readme/both-sides-move-on.sh"
```
-->

<div align="center">

![Monorepo commits a to d, with HEAD at d and boundary at a, the clone of k; library commits k to n, theirs at n; ours is d prime, the rebuilt b prime and d prime on top of k, which is U(boundary) and base](docs/09-scenarios/01-everyday-sync/01-sync-model/before-pull-git-names.drawio.svg)

</div>

`push` rebuilds only the commits that changed `lib/`, in the library's
layout. `status` compares that rebuild with the fetched upstream:

```scrut
$ git splice status
On branch main

  ahead 2, behind 3  lib
```

`git splice pull lib` merges upstream changes into one monorepo commit;
`git splice push lib` publishes the rebuilt library history.
See the [sync model](docs/03-concepts/02-sync-model.md) for the details,
and [upstream worktrees](docs/06-command-reference/02-fetch.md#looking-at-an-upstream)
to work directly on the library's history.

## Why not X?

Compare the same workflow with
[Git's own tools](docs/05-comparisons/01-git/README.md) and
[third-party tools](docs/05-comparisons/02-third-party/README.md),
including `git submodule`, `git subtree`, `git-subrepo` and Josh.

## Contribute

- [Contributing](docs/10-contributing/README.md)

## License

MIT, see [LICENSE](LICENSE).
