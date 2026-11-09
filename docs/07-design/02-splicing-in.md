# Splicing in

## Starting a splice: `clone` and `init`

| Situation | Command |
|---|---|
| Upstream exists, the folder doesn't | `git splice clone <url> [<path>]` |
| The folder exists, upstream is new or empty | `git splice init <path> <url>` |
| Both exist with the same content | `git splice clone <url> <path>`: only writes `.splice`, since nothing can be lost |
| Both exist and differ | `git splice clone --merge <url> <path>` |

- `clone` refuses a folder that exists and differs from upstream, like
  `git clone` refuses a non-empty directory. The message names `--merge`.
- `--merge` runs the same mechanism as `merge` (below), with an empty
  folder as the merge base. Every file that differs becomes an add/add
  conflict, and nothing is lost. Deleting the folder on a branch,
  re-cloning it there and merging `main` back **isn't** a substitute: the
  merge base still has the folder, so Git takes upstream's side wholesale
  and drops local-only files.
- To replace the folder with upstream's version instead, `git rm` it in one
  commit, then `clone` into the empty spot.
- `init` refuses an upstream that already has commits, and points to
  `clone --merge`. It writes `.splice` without a synced commit, and the
  first push creates the upstream branch starting at the init commit,
  followed by any commits after it, also on a feature branch where the
  folder didn't change. The folder's history before it isn't
  published: it was written
  for the monorepo, and may hold what was removed before anyone decided
  to publish the folder
  ([example](../09-scenarios/02-starting-a-splice/04-init-new-upstream/01-removed-before-init/README.md)).
- The name `add` is avoided on purpose: it suggests `git add`.

## Splicing in: `merge`, and `pull` = `fetch` + `merge`

`merge` turns already fetched upstream changes into **one ordinary
commit** in the monorepo, and never touches the network. The problem it
solves: upstream's commits have the splice's content at their root, while
the monorepo has it at `<path>/`, and they share no history, so Git can't
merge them directly. `git subtree` solves that by putting upstream's
history into the monorepo's. `merge` instead supplies the merge base
explicitly:

1. Build two throwaway commits whose trees have the monorepo's layout
   (`reroot_tree`, using a temporary index):
   - **base:** `HEAD`'s tree, with `<path>/` replaced by the merge base's
     tree and HEAD's `.splice`.
   - **theirs:** `HEAD`'s tree, with `<path>/` replaced by the upstream branch's
     tree and a `.splice` that records its commit. Its parent is base.
2. Run `git cherry-pick theirs`. That's a three-way merge of `HEAD` (ours)
   and theirs, with base as the merge base. Only `<path>/` differs between
   base and theirs, so only the splice can conflict. Local edits are kept, and the
   `.splice` update comes along in the same commit. Git's ort merge does
   the work, including rename detection.

The merge base is `git merge-base R T`
([why](../03-concepts/02-sync-model.md#how-r-and-t-determine-the-status)).

**The same files, another history:** if the folder already has T's
files, there's nothing to merge. But if T isn't part of R's history,
`merge` still records T as U(H), in a commit that only changes `.splice`.
That happens when the upstream rewrote its history to the same files
([example](../09-scenarios/06-rewritten-history/02-upstream-rewritten-equal-tree/README.md)),
squash-merged what was pushed, or got R edited before the push
([example](../09-scenarios/06-rewritten-history/01-edited-before-push/README.md)).
Without the record, R would keep the monorepo's original commits, and
the next push would publish them. Right after an ordinary push, R is T,
and nothing is recorded. Once the folder changes again, it's too late:
the splice reads as diverged, or as unrelated history.

- **On a conflict:** resolve it, then run `git commit`, which finishes the
  cherry-pick and keeps the prepared message. Abort with
  `git cherry-pick --abort`. `git status` says "cherry-picking" although
  you ran `merge`, so `merge` names both commands when it stops.
- **base and theirs are never referenced** and get garbage-collected. Upstream
  commits stay in `refs/splices/` and never become ancestors of `HEAD`.
- **Nested splices:** a pull of a splice brings in the `.splice` files
  below it as its upstream has them, and becomes the last sync of those
  splices. If its upstream moved the synced commit of a splice below, the
  rebuild joins that splice's unpushed commits with the new one, as after
  a pull of a divergence. `pull` fetches the splices below too, so their
  new synced commit is there.
  - **Top-down:** `merge` and `pull` take a splice before the ones below
    it. Pulling the one below first, to a commit newer than the one the
    upstream above records, would make the pull above conflict. A pull
    that removed a `.splice` below ends that splice, and its pull is
    skipped. A failed fetch stops the pull of the splices above and below
    it, and a failed merge the merges below it.
  - **Bottom-up:** `push` takes a splice before the ones above it, whose
    push publishes its `.splice`, and a failed push stops them. Otherwise
    the upstream above would record content the upstream below doesn't
    have.
