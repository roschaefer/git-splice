# Git-compatible VCS

Jujutsu (`jj`) and Sapling (`sl`) can share a repository with Git.
`git-splice` can work with their ordinary files, but currently relies on
Git's selected branch and view of the working copy. Supporting these
tools means deciding how their state maps to Git's.

The shared proposal is [explicit upstream branch selection](README.md#extensions-to-syncing).
The comparisons describe current support for
[Jujutsu](../../05-comparisons/03-vcs/02-jj.md) and
[Sapling](../../05-comparisons/03-vcs/01-sapling.md); this page covers
what integration would need.

## Two branches

The existing [branch selection rules](../03-upstreams.md#branch-selection-follows-the-project)
need two names:

| Name | Purpose | Possible source |
| --- | --- | --- |
| Current branch | Select the upstream branch for a sync | An explicit branch, or an unambiguous bookmark near the working copy |
| Default branch | Map the monorepo's default to the upstream's `default-branch` | Git's default branch; in jj, the bookmark named by `trunk()` |

jj has no current bookmark, and commits don't move one automatically.
Inferring a branch from `@-` or its ancestors must handle missing, stale
or multiple bookmarks. Sapling keeps Git on its branch after
`sl commit`, but `sl goto` detaches `HEAD`; `sl goto main` selects
`origin/main`, not the local branch.

Jujutsu support is tracked in
[#41](https://github.com/roschaefer/git-splice/issues/41).

## Working copies and commits

| Tool | What integration must account for |
| --- | --- |
| Jujutsu | Choose between the working-copy commit `@` and its parent `@-`, and decide where `pull` and `clone` commit. Git sees changes in `@` as uncommitted; jj imports a new Git commit on its next command. |
| Sapling | Preserve staged changes even when `sl amend` leaves Git's index stale. A native `sl clone` has no Git working copy for `git-splice` to operate on. |

The scenarios reproduce the
[jj branch workaround](../../09-scenarios/09-vcs-compatibility/03-jujutsu-named-branch/README.md)
and [Sapling's index and branch state](../../09-scenarios/09-vcs-compatibility/02-sapling-git-index/README.md).

## Import Sapling's sync records

Sapling records the upstream URL, commit and destination folder in a
commit header. An import command could read the newest record and write
`.splice`, much as `clone --from-submodule` converts a submodule. The
recorded commit would become the sync point without fetching it again.
The folder could then use `git splice push` to send fixes back.
If a Git squash had already dropped the newest record, the import would
take an older one, with the wrong merge base described below; the
remaining records don't show that one is missing.

`.splice` has no source-path key: it represents the upstream root.
The import would reject records with a nonempty source folder, since
syncing those against the root would change what is compared or pushed.

Keeping both formats in sync would be harder:

| Approach | Limit |
| --- | --- |
| Read Sapling's header instead of `.splice` | A Git squash drops it. Falling back to an older record can pick the wrong merge base. |
| Write Sapling's header on each pull | Requires writing a custom commit header and depending on Sapling's format. |

The [metadata scenario](../../09-scenarios/09-vcs-compatibility/01-sapling-metadata/README.md)
shows a deleted file returning after a squash loses the newer record.
Sapling record import and writing both formats are not planned yet.
