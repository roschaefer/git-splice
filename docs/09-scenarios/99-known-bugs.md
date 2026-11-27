# Known bugs and limitations

Some scenarios explore how `git-splice` behaves where a reader might
not expect it, and show the workarounds. They show it as it is today, so
the output stays real and the page changes when the behaviour does. A
banner under each one's title says where the problem stands, and the
section here that lists it:

- **[Known bug](#known-bugs):** we want to fix it, and an open issue
  tracks the fix.
- **[Undecided](#undecided):** whether to change it is open, and an
  open issue holds the question.
- **[Limitation](#limitations):** we decided to keep it, often because a
  fix would cost more than a rare case is worth. No issue tracks it.

A problem without a scenario is only in the
[issue list](https://github.com/roschaefer/git-splice/issues).

## Known bugs

| Scenario | Issue | What goes wrong today |
| --- | --- | --- |
| [up-to-date: a monorepo commit as the synced commit](01-everyday-sync/02-up-to-date/monorepo-commit-as-synced-commit.md) | [#7](https://github.com/roschaefer/git-splice/issues/7) | A push builds on the commit `.splice` names, so a monorepo commit there publishes the monorepo's history. |
| [monorepo-line-endings: attributes added later](02-starting-a-splice/08-clone-from-submodule/04-monorepo-line-endings/README.md) | [#311](https://github.com/roschaefer/git-splice/issues/311) | A `.gitattributes` rule added after the line `clone` asked for applies to the splice's files again, and no command says so. |
| [upstream-macro](02-starting-a-splice/08-clone-from-submodule/06-upstream-macro/README.md) | [#311](https://github.com/roschaefer/git-splice/issues/311) | `clone` refuses an upstream whose `.gitattributes` defines a macro; a copy of the definition in the monorepo's root `.gitattributes` gets past it. |
| [lfs-upstream](04-upstreams/08-lfs-upstream/README.md) | [#407](https://github.com/roschaefer/git-splice/issues/407) | `clone` of an upstream that stores files in Git LFS fails; Git LFS isn't supported yet. |
| [lfs-upstream: retrained-upstream](04-upstreams/08-lfs-upstream/01-cloned-by-hand/01-retrained-upstream/README.md) | [#407](https://github.com/roschaefer/git-splice/issues/407) | `pull` of a changed Git LFS file fails, as `clone` does. |
| [nested-splices: a pull retried after the synced commit below is gone](05-nested-splices/01-nested-splices/gone-below.md) | [#274](https://github.com/roschaefer/git-splice/issues/274) | A retry of a failed pull succeeds, though the splice below still lacks its synced commit. |
| [nested-splices: spliced elsewhere before the push below](05-nested-splices/01-nested-splices/spliced-elsewhere-before-the-push-below.md) | [#467](https://github.com/roschaefer/git-splice/issues/467) | After a push of the splice above alone, `git splice clone` of its upstream can't make the inner splice's synced commit again. |
| [nested-splices: a and b swap their `.splice`](05-nested-splices/01-nested-splices/swapped-ids.md) | [#174](https://github.com/roschaefer/git-splice/issues/174) | A push sends one splice's files to the other's upstream. |
| [cycle](05-nested-splices/04-cycle/README.md) | [#86](https://github.com/roschaefer/git-splice/issues/86) | A splice whose upstream splices the monorepo back in nests the monorepo one level deeper on every pull; nothing refuses it. |
| [edited-before-push: a change before the pull](06-rewritten-history/01-edited-before-push/change-before-the-pull.md) | [#82](https://github.com/roschaefer/git-splice/issues/82) | The next push publishes the original commit next to its edited version; `pull -s ours` isn't implemented. |
| [upstream-rewritten-equal-tree: `push --force`](06-rewritten-history/02-upstream-rewritten-equal-tree/push-force-undoes-the-rewrite.md) | [#38](https://github.com/roschaefer/git-splice/issues/38) | `push --force`, one of the ways out `merge` prints, publishes the history the upstream rewrote away. |
| [mirrors: mirrors that swap paths](07-moved-folders/03-mirrors/swapped-paths.md) | [#193](https://github.com/roschaefer/git-splice/issues/193) | After two mirrors swap paths, each path keeps its own history, so a push can publish what a mirror removed. |
| [jujutsu-named-branch](09-vcs-compatibility/03-jujutsu-named-branch/README.md) | [#41](https://github.com/roschaefer/git-splice/issues/41) | In a colocated jj repository, syncing needs a named Git branch, which jj doesn't keep selected; it has to be selected again for each sync. |

## Undecided

None at the moment.

## Limitations

| Scenario | What happens | Way out |
| --- | --- | --- |
| [clone-from-submodule, with a nested submodule, pushed](02-starting-a-splice/08-clone-from-submodule/07-nested-submodules/README.md) | After `clone --from-submodule --recursive`, the next push of the folder above turns the upstream's own submodules into splices there too. | If that upstream's owners keep their submodules, push to a fork of yours. |
| [splice-refs: key renamed while fetching](04-upstreams/05-splice-refs/renamed-while-fetching.md) | A `git splice key` in another worktree during a fetch, pull or push leaves the fetched refs under the old key, and the splice looks up to date until the next fetch. | Fetch again, then delete the refs left under the old key. |
| [splice-refs: two fetches at once](04-upstreams/05-splice-refs/two-fetches-at-once.md) | Two fetches at once, in two worktrees, may both move one ref, and one fails with `cannot lock ref`. | Run it again. |
| [encrypted-upstream: the `.splice` in plaintext](04-upstreams/09-encrypted-upstream/splice-in-plaintext.md) | The `.splice` stays out of git-crypt's filter, so whoever reads the monorepo reads it, the upstream's URL included. | Keep nothing secret in the URL. |
| [non-UTF-8 input](10-platform-compatibility/01-platform-restrictions/README.md) | Arguments, repository and splice paths, and author or committer identities that aren't UTF-8 are refused, not changed. | Rename paths, and rewrite identities to UTF-8, before using them with `git-splice`. |
| [paging output on Windows](10-platform-compatibility/01-platform-restrictions/windows-paging.md) | `log` and `diff` write to the terminal without a pager. | Pipe the output to a pager. |

## Every entry

This check lists every document with a banner, what it says, and its
issue. It fails if the tables above don't link exactly these documents,
each in the section its banner names:

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/readme-setup.sh"
```
-->

```scrut {output_stream: combined}
$ check_known_bugs
ok 01-everyday-sync/02-up-to-date/monorepo-commit-as-synced-commit.md bug #7
ok 02-starting-a-splice/08-clone-from-submodule/04-monorepo-line-endings/README.md bug #311
ok 02-starting-a-splice/08-clone-from-submodule/06-upstream-macro/README.md bug #311
ok 02-starting-a-splice/08-clone-from-submodule/07-nested-submodules/README.md limitation
ok 04-upstreams/05-splice-refs/renamed-while-fetching.md limitation
ok 04-upstreams/05-splice-refs/two-fetches-at-once.md limitation
ok 04-upstreams/08-lfs-upstream/01-cloned-by-hand/01-retrained-upstream/README.md bug #407
ok 04-upstreams/08-lfs-upstream/README.md bug #407
ok 04-upstreams/09-encrypted-upstream/splice-in-plaintext.md limitation
ok 05-nested-splices/01-nested-splices/gone-below.md bug #274
ok 05-nested-splices/01-nested-splices/spliced-elsewhere-before-the-push-below.md bug #467
ok 05-nested-splices/01-nested-splices/swapped-ids.md bug #174
ok 05-nested-splices/04-cycle/README.md bug #86
ok 06-rewritten-history/01-edited-before-push/change-before-the-pull.md bug #82
ok 06-rewritten-history/02-upstream-rewritten-equal-tree/push-force-undoes-the-rewrite.md bug #38
ok 07-moved-folders/03-mirrors/swapped-paths.md bug #193
ok 09-vcs-compatibility/03-jujutsu-named-branch/README.md bug #41
ok 10-platform-compatibility/01-platform-restrictions/README.md limitation
ok 10-platform-compatibility/01-platform-restrictions/windows-paging.md limitation
```

## Adding an entry

1. Put the banner on the line after the document's title, with a
   relative link to this page. From a scenario at the top of its
   chapter, that's `../../99-known-bugs.md`, with one more `../` per
   level below. A known bug or an undecided one names its open issue:

       > **Known bug, [#N](https://github.com/roschaefer/git-splice/issues/N).** This page shows what `git-splice` does today, bug included. See [known bugs and limitations](../../99-known-bugs.md#known-bugs).

       > **Undecided, [#N](https://github.com/roschaefer/git-splice/issues/N).** This page shows what `git-splice` does today; whether to change it is open. See [known bugs and limitations](../../99-known-bugs.md#undecided).

       > **Limitation.** This page shows behaviour `git-splice` keeps on purpose, and the way out. See [known bugs and limitations](../../99-known-bugs.md#limitations).

2. Add a row to the banner's section above.
3. Run `just docs-check --write` and read the new line under "Every
   entry".

When the state changes, change the banner and move the row in the same
PR: when a bug is fixed, remove both; when a question is decided, the
page becomes a known bug or a limitation, and a limitation's issue is
closed.
