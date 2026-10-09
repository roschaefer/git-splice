# Package managers

git splice isn't meant to become a package manager. But since splices can
nest, they form a dependency graph, and a package manager like npm, Yarn
or Cargo has solved many of the same problems. This page collects what
maps, and what doesn't.

## What maps

| Package manager | git splice |
|---|---|
| package name | upstream ([upstreams](../../test/concepts/upstreams/README.md)) |
| what you ask for: a version range or tag, e.g. `^1.2` (a *descriptor* in Yarn) | the upstream branch a splice syncs with |
| what you got: the exact version in the lockfile (a *locator* in Yarn) | the synced commit U |
| a dependency declaring its own dependencies | a nested `.splice`, which travels with the upstream above ([nesting](../../test/concepts/nesting/README.md)) |
| registries and mirror servers | several upstreams per splice ([several-upstreams](../../test/scenarios/several-upstreams/README.md)) |
| two versions of one package in the tree | independent splices of one upstream, at two versions ([upstreams](../../test/concepts/upstreams/README.md#one-library-at-two-versions)) |
| one package, deduplicated | mirrors: splices with the same `id` ([mirrors](mirrors.md)) |
| `yarn dedupe --check` | a report of mirrors that drifted, not yet |
| — | the [`id`](../../test/concepts/splice-identity/README.md): which copies are one splice, history included. A package can't be edited in place, so its name and version say that already |

A package name is one identity in a registry. A URL is only a location:
two URLs of one repository are two upstreams to the monorepo
([upstreams](../../test/concepts/upstreams/README.md#one-repository-two-urls)).

## What doesn't: reference versus containment

A package manager **refers** to packages. It builds a graph keyed by
name and version, and installs each package once, wherever it's needed:

- **Diamonds** get one copy, if the version ranges allow it.
- **Cycles** are allowed in npm, since installing a package that's
  already installed is a no-op. Node finds a package by walking up the
  `node_modules` folders, so a dependency that a folder above provides
  needs no copy of its own.

A splice **contains** its files, and a nested splice is part of the
files of the splice above. So:

- **Diamonds** get a copy per path, which can be at different versions
  ([diamond](../../test/concepts/nesting/diamond.md)).
- **Cycles** never end, and aren't supported, though not prevented yet
  ([cycle](../../test/concepts/nesting/cycle.md)).

Containment is the point of git splice, not an accident: a splice's
upstream is complete on its own, and anyone can clone it without git
splice. And you can change a splice in place, and send the change back
with `push`. A package manager can only patch a package (`yarn patch`,
`patch-package`) or link a local copy (`link:`, `portal:`).

## What could be learned

- **A drift report**, as `yarn dedupe --check` reports packages that
  could share a version: mirrors whose files differ
  ([mirrors](mirrors.md)).
- **Skipping a cycle instead of refusing it**, as Node does: a splice
  that's already above needs no copy below. It would need a reference
  where today there is content.

## Zero installs

Yarn's *zero installs* commit the package cache, so a fresh clone runs
without an install step. A splice has that already: its files are
committed in the monorepo, and a clone of the monorepo has them, with no
fetch ([splice-refs](../../test/scenarios/splice-refs/README.md#a-clone-of-the-monorepo-has-no-splice-refs)).

The difference is what's committed. Yarn commits one compressed archive
per package version, deduplicated across the graph, plus a map of where
each one is used. A splice commits plain source files, once per copy.
Git stores identical files once, but the checkout and every diff has
each copy. And a package is usually built before it's published, e.g.
from TypeScript, while a splice has the upstream's sources, so it is
built as part of the monorepo.

## Explicit branches

What a splice asks for is implicit today: the upstream branch named like
the monorepo's current branch ([design](../design/README.md#branches)).
A package manager writes it down, as a range in `package.json`. A splice
could do the same, with a branch in `.splice` or a `--branch` per
command.

That would help [Jujutsu](https://github.com/jj-vcs/jj) (`jj`) in
particular. In a colocated repository, jj leaves Git's `HEAD` detached,
and has bookmarks instead of a current branch. git splice stops on a
detached `HEAD`, since it has no branch name to follow
([#41](https://github.com/roschaefer/git-splice/issues/41)). An explicit
branch would make the current branch only a default.
