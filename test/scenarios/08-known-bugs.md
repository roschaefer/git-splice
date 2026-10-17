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
| [nested-splices: a and b swap their `.splice`](05-nested-splices/01-nested-splices/swapped-ids.md) | [#174](https://github.com/roschaefer/git-splice/issues/174) | A push sends one splice's files to the other's upstream. |
| [edited-before-push: a change before the pull](06-rewritten-history/01-edited-before-push/change-before-the-pull.md) | [#82](https://github.com/roschaefer/git-splice/issues/82) | The next push publishes the original commit next to its edited version; `pull -s ours` isn't implemented. |
| [upstream-rewritten-equal-tree: `push --force`](06-rewritten-history/02-upstream-rewritten-equal-tree/push-force-undoes-the-rewrite.md) | [#38](https://github.com/roschaefer/git-splice/issues/38) | `push --force`, one of the ways out `merge` prints, publishes the history the upstream rewrote away. |
| [moved-with-unpushed-commits](07-moved-folders/01-moved-with-unpushed-commits/README.md) | [#4](https://github.com/roschaefer/git-splice/issues/4) | A `git mv` squashes unpushed commits into the move. Workaround: [push before moving](07-moved-folders/01-moved-with-unpushed-commits/push-before-moving.md). |
| [swapped-splices](07-moved-folders/02-swapped-splices/README.md) | [#4](https://github.com/roschaefer/git-splice/issues/4) | Two folders that trade places fold unpushed work into the swap commit. |

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
ok 05-nested-splices/01-nested-splices/swapped-ids.md #174
ok 06-rewritten-history/01-edited-before-push/change-before-the-pull.md #82
ok 06-rewritten-history/02-upstream-rewritten-equal-tree/push-force-undoes-the-rewrite.md #38
ok 07-moved-folders/01-moved-with-unpushed-commits/README.md #4
ok 07-moved-folders/02-swapped-splices/README.md #4
```

## Adding a known bug

1. Put the banner on the line after the document's title, with the
   issue and a relative link to this page:

       > **Known bug, [#N](https://github.com/roschaefer/git-splice/issues/N).** This page shows what `git-splice` does today, bug included. See [all known bugs](../known-bugs.md).

2. Add a row to the table above.
3. Run `just docs-check --write` and read the new line under "Every
   known bug".

When the issue is fixed, remove the banner and the row in the same PR.
