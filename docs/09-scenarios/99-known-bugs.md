# Known bugs

Most scenarios show what `git-splice` should do. The documents listed
here also show behaviour that is wrong, tracked by an open issue. They
show it as it is today, so the output stays real and the page changes
when the issue is fixed. Each has a banner under its title that links
back here.

| Scenario | Issue | What goes wrong today |
| --- | --- | --- |
| [init-then-cloned](02-starting-a-splice/05-init-then-cloned/README.md) | [#11](https://github.com/roschaefer/git-splice/issues/11) | Until a fresh clone fetches, the upstream reads as empty though it has commits. |
| [init-then-cloned: push before the fetch](02-starting-a-splice/05-init-then-cloned/push-before-fetch.md) | [#11](https://github.com/roschaefer/git-splice/issues/11) | A push before the first fetch says it creates the upstream branch, which already exists. |
| [bumped-on-a-feature-branch: moved after the bump](03-branches-and-teamwork/08-bumped-on-a-feature-branch/moved-after-the-bump.md) | [#466](https://github.com/roschaefer/git-splice/issues/466) | A synced commit that a bump recorded and the upstream lost isn't made again once the splice moved since. |
| [lfs-upstream](04-upstreams/08-lfs-upstream/README.md) | [#407](https://github.com/roschaefer/git-splice/issues/407) | `clone` of an upstream that stores files in Git LFS fails; Git LFS isn't supported yet. |
| [lfs-upstream: retrained-upstream](04-upstreams/08-lfs-upstream/01-cloned-by-hand/01-retrained-upstream/README.md) | [#407](https://github.com/roschaefer/git-splice/issues/407) | `pull` of a changed Git LFS file fails, as `clone` does. |
| [nested-splices: a pull retried after the synced commit below is gone](05-nested-splices/01-nested-splices/gone-below.md) | [#274](https://github.com/roschaefer/git-splice/issues/274) | A retry of a failed pull succeeds, though the splice below still lacks its synced commit. |
| [nested-splices: spliced elsewhere before the push below](05-nested-splices/01-nested-splices/spliced-elsewhere-before-the-push-below.md) | [#467](https://github.com/roschaefer/git-splice/issues/467) | After a push of the splice above alone, `git splice clone` of its upstream can't make the inner splice's synced commit again. |
| [nested-splices: a and b swap their `.splice`](05-nested-splices/01-nested-splices/swapped-ids.md) | [#174](https://github.com/roschaefer/git-splice/issues/174) | A push sends one splice's files to the other's upstream. |
| [edited-before-push: a change before the pull](06-rewritten-history/01-edited-before-push/change-before-the-pull.md) | [#82](https://github.com/roschaefer/git-splice/issues/82) | The next push publishes the original commit next to its edited version; `pull -s ours` isn't implemented. |
| [upstream-rewritten-equal-tree: `push --force`](06-rewritten-history/02-upstream-rewritten-equal-tree/push-force-undoes-the-rewrite.md) | [#38](https://github.com/roschaefer/git-splice/issues/38) | `push --force`, one of the ways out `merge` prints, publishes the history the upstream rewrote away. |

## Input and platform restrictions

These current restrictions are separate from the open-issue bugs above.
The linked pages show the behaviour and available workarounds.

- [Non-UTF-8 input](10-platform-compatibility/01-platform-restrictions/README.md):
  arguments, repository and splice paths, and author/committer identities.
- [Splice paths must be ref-friendly](02-starting-a-splice/06-clone-without-commits/ref-friendly-path.md):
  spaces and other ref-name characters are currently refused.
- [Paging on Windows](10-platform-compatibility/01-platform-restrictions/windows-paging.md):
  pipe output to a pager explicitly.

## Every known bug

This check lists every document with a banner, and its issue. It fails
if the table above doesn't link exactly these documents:

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/readme-setup.sh"
```
-->

```scrut {output_stream: combined}
$ check_known_bugs
ok 02-starting-a-splice/05-init-then-cloned/README.md #11
ok 02-starting-a-splice/05-init-then-cloned/push-before-fetch.md #11
ok 03-branches-and-teamwork/08-bumped-on-a-feature-branch/moved-after-the-bump.md #466
ok 04-upstreams/08-lfs-upstream/01-cloned-by-hand/01-retrained-upstream/README.md #407
ok 04-upstreams/08-lfs-upstream/README.md #407
ok 05-nested-splices/01-nested-splices/gone-below.md #274
ok 05-nested-splices/01-nested-splices/spliced-elsewhere-before-the-push-below.md #467
ok 05-nested-splices/01-nested-splices/swapped-ids.md #174
ok 06-rewritten-history/01-edited-before-push/change-before-the-pull.md #82
ok 06-rewritten-history/02-upstream-rewritten-equal-tree/push-force-undoes-the-rewrite.md #38
```

## Adding a known bug

1. Put the banner on the line after the document's title, with the
   issue and a relative link to this page. From a scenario at the top of
   its chapter, that's `../../99-known-bugs.md`, with one more `../` per
   level below:

       > **Known bug, [#N](https://github.com/roschaefer/git-splice/issues/N).** This page shows what `git-splice` does today, bug included. See [all known bugs](../../99-known-bugs.md).

2. Add a row to the table above.
3. Run `just docs-check --write` and read the new line under "Every
   known bug".

When the issue is fixed, remove the banner and the row in the same PR.
