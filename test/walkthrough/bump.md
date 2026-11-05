# Bumping the sync point

After a push, the upstream has your commits, but the monorepo's `.splice`
still names the upstream commit from before: a push
[never writes to the monorepo](../concepts/sync-model/README.md#r-is-computed-not-stored).
The next push still works, since it sends only what isn't upstream yet.
`git splice pull --bump` records the pushed commit anyway, in a
commit that only changes `.splice`, much like a submodule bump. Here the
monorepo pushed *b*, *d* and *e* as *b'*, *d'* and *e'*, then bumped in *f*
([scenario](../scenarios/01-everyday-sync/01-sync-model/01-after-pull/01-pushed/README.md)):

| After the push | After the bump |
|---|---|
| ![After the push: e is H, U(H) = n, B is a, U(B) = k, and T and R point at e prime](../scenarios/01-everyday-sync/01-sync-model/01-after-pull/01-pushed/pushed.drawio.svg) | ![After the push and the bump: the bump commit f is H and B, U(H) = U(B) = e prime, and T and R point at e prime too](../scenarios/01-everyday-sync/01-sync-model/01-after-pull/01-pushed/pushed-and-bumped.drawio.svg) |

Before the bump, `.splice` still names *n*, from the last pull, so B
stays at *a*. After it, `.splice` names *e'*, and *f* is the new B.

## When to bump

Rebuilds, bisects and the history of a new splice id start from the
commit `.splice` names. Until a bump, that's the one from before the push:

- **Speed:** every rebuild copies the pushed commits again
  ([scenario](../scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/01-pushed-then-pulled/bump-after-push.md)).
- **Bisect:** bisecting into the next pull also searches the pushed
  commits, though that pull didn't bring them in
  ([scenario](../scenarios/03-branches-and-teamwork/05-bisect-into-a-pull/01-after-a-push/README.md)).
- **A new [splice id](../concepts/splice-identity/README.md):** required.
  Without a bump first, the next push is refused
  ([scenario](../scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/01-pushed-then-pulled/new-id-after-push.md)).

## When not to bump

On a feature branch. Two branches that record different commits in
`.splice` conflict when they're merged, even where the files would merge
cleanly. Without a bump,
a feature branch leaves `.splice` alone, and a merge takes `main`'s. So
when the library squash-merges its pull requests, a bump on the
monorepo's `feature` causes trouble either way:

| The monorepo merges `feature`… | Then | Way out |
|---|---|---|
| after the library squash-merged | `.splice` conflicts: `main` names the squashed *s*, `feature` the pull request's *b'*. | Rebase the library's `feature` onto its `main`, then pull on `feature`. |
| before the library squash-merged | `main`'s `.splice` names the pull request's commit. Once the library deletes the branch, a fresh clone can't fetch it. | Don't bump on `feature`. |

<div align="center">

![The monorepo commits a and d on main, and b and c on feature, both from a; in the lane vendor/a/, s on main and b prime on feature, both on top of k; U(d) is s and U(c) is b prime](../scenarios/03-branches-and-teamwork/08-bumped-on-a-feature-branch/bump-conflict.drawio.svg)

</div>

The rebase needs a library branch you can force-push. For a library you
don't maintain, that's a branch in your company's fork of it
([contributing through a fork](fork.md)). A
[scenario](../scenarios/03-branches-and-teamwork/08-bumped-on-a-feature-branch/README.md) runs both cases and the way out.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

## Bump on main, after a push

Bring `pkg-a` up to date, as in the [main walkthrough](README.md#pull),
then change it and push:

```scrut
$ git splice pull vendor/pkg-a >/dev/null &&
>   echo "a faster parser" >>vendor/pkg-a/file.txt &&
>   git commit -qam "k: a faster parser"
```

```scrut
$ git splice push vendor/pkg-a
ok   vendor/pkg-a: pushed dd60ba4 to main
```

A plain pull would find nothing to pull. With `--bump`, it records the
pushed commit:

```scrut
$ git splice pull --bump -m "a: bump pkg-a to the faster parser" vendor/pkg-a
ok   vendor/pkg-a fetched
ok   vendor/pkg-a: bumped the synced commit to dd60ba4
```

```scrut
$ git log -1 --format=%s "$(git config --file vendor/pkg-a/.splice splice.commit)"
k: a faster parser
```
