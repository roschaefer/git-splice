# Splicing out

## Splicing out: `push` and the rebuild

A push sends the splice's history since the last sync, rebuilt as upstream
commits. `rebuild_splice` is a function of `HEAD` alone:

1. **Find the last sync.** *L* is
   `git log --first-parent -1 -- <path>/.splice`. Every `clone`, `init`
   and pull writes such a commit, and no rebase or squash merge can remove
   all of them. U(L) is the synced commit recorded at *L*. A `git mv` of
   the whole folder that leaves `.splice` as it was isn't a last sync:
   the rebuild follows the folder to its old path, by its id.
2. **Start at U(L).** If *L*'s folder (without `.splice`) equals U(L)'s
   tree, *L* is B, and the rebuild continues from U(L). Otherwise a pull
   merged a divergence, or a squash merge mixed local edits into *L*, and
   *L* is rebuilt too, on the parents the
   [sync model](../03-concepts/02-sync-model.md#parents-of-rebuilt-commits)
   picks, back to [B](../03-concepts/02-sync-model.md#where-b-is)
   ([scenario](../09-scenarios/01-everyday-sync/02-up-to-date/03-diverged-then-pulled/README.md)).
   Without U(L), e.g. after `init`, the rebuild starts at the mount, as a
   root commit.
3. **Copy each commit.** For each commit in
   `git rev-list --reverse --first-parent L..HEAD -- <path>` whose folder
   changed, `git commit-tree` with the folder's tree minus `.splice`.
   Author and committer are copied, **including their dates**, as
   `git subtree split`'s `copy_commit` does. The message is read with
   `--pretty=format:%B`, not `--format=`, which would add a newline.
   Commits are never signed: a signature would differ from run to run.

**First parent only:** a merge in the monorepo, e.g. `git merge main` on a
feature branch, becomes **one ordinary commit** upstream, with the merge's
message. Upstream doesn't know the monorepo's side branches, so a faithful
merge shape would add nothing, and leaving it out avoids the
parent-mapping problems `split` spent years fixing.

**Only this splice's history:** a splice's history starts at its
*mount*, the newest first-parent commit whose first parent had no
`.splice` at the path, or one with another `id`. Before the
mount, the folder was no splice, or another one, so nothing from there is
published, with or without a synced commit. That covers a folder's
history from before `init`
([example](../09-scenarios/02-starting-a-splice/04-init-new-upstream/01-removed-before-init/README.md)),
two splices that swap paths
([example](../09-scenarios/07-moved-folders/02-swapped-splices/README.md)), and a splice
removed and spliced in again
([example](../09-scenarios/02-starting-a-splice/04-init-new-upstream/02-unspliced-then-cloned-again/README.md)).
A `git mv` keeps it too: the rebuild follows the folder back to the path
whose `.splice` had the same `id` in the commit before, also when two
splices swap paths, or a new folder takes the old one.
A new upstream URL keeps the history: the `id` stays
([example](../09-scenarios/04-upstreams/04-upstream-moved/README.md)).

**A nested splice's history up to the splice above's last sync** comes
from that splice's upstream, at its synced commit
([nesting](../03-concepts/04-nesting.md),
[example](../09-scenarios/05-nested-splices/01-nested-splices/spliced-elsewhere.md)).
Of the splices above, it takes the one with the newest last sync, and on
a tie the outermost: a push writes nothing to the monorepo, so the
`.splice` of the splice in between may name a commit from before the
change, while the outermost upstream has it
([three levels](../09-scenarios/05-nested-splices/01-nested-splices/02-three-levels/README.md)).
Only if the upstream above has the same splice there, by its `id`
([replaced above](../09-scenarios/05-nested-splices/01-nested-splices/replaced-above.md)).
And the monorepo's own commits before the last sync are joined in even if
the folder's files equal that rebuild, so a commit pushed straight to
the splice's upstream stays in its history
([pushed and made above](../09-scenarios/05-nested-splices/01-nested-splices/pushed-and-made-above.md)).

**Costs** O(commits since B), not O(all history). The commit loop
reads all commit metadata with one `git log` and all folder trees with one
`git cat-file --batch-check`, so it spawns about one process per commit.

**Never writes to the monorepo**
([why](../03-concepts/02-sync-model.md#r-is-computed-not-stored)).

**A new upstream branch** is created only if R has commits that
upstream's default branch lacks, which a PR from the new branch would
show. So starting a feature branch doesn't create empty branches on every
upstream, while commits the default branch lacks always count: the ones
the feature branch got from the branch it was cut from, and the first
push of a splice made by `init`, which has no upstream branch at all.
Whether the folder changed on this branch doesn't matter. A branch
stacked on one upstream has already gets its own branch upstream too,
with nothing new
([scenario](../09-scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/01-feature-branch-changed/01-stacked-branch/README.md)).

## `status`: the sync state

`classify_splice` works the state out each time, from R and T, as the
[sync model](../03-concepts/02-sync-model.md#how-r-and-t-determine-the-status)
describes. It compares the files first: when they're equal, nothing
needs rebuilding. Before that, it checks there's something to compare:
without `refs/splices/<key>/*`, and with U(H) recorded but not available
locally, as in a fresh clone of the monorepo, the splice was never
fetched.

## `diff` and `log`

- **`diff`** shows the file changes a push would send: `git diff T R`, or,
  for a missing upstream branch, from the merge base of R and upstream's
  default branch, as a PR from the new branch would show them.
- **`log`** shows commits in both directions:

  ```
  git log --left-right --cherry-mark R...refs/splices/<key>/heads/<branch>
  ```

  `<` is on the left (local) side only, so a push sends it; `>` is on the
  upstream side only, so a pull brings it; `=` is a commit upstream already
  applied by cherry-pick or rebase. Ours on the left, theirs on the right,
  as in Git's conflict markers. The format shows the author, because a
  push publishes it and it may be a private identity.
