# Splicing in

## Preserve existing work when starting a splice

`clone` starts from an existing upstream; `init` starts from an existing
folder and an empty upstream. The
[command reference](../06-command-reference/01-clone.md) covers their syntax.
The design choices are about preserving existing work:

- An existing folder that matches upstream needs only `.splice`. If the
  files differ, `clone` refuses and names `--merge` instead of overwriting.
- `clone --merge` uses an empty folder as the three-way merge base. Files
  changed on both sides become add/add conflicts; local-only files survive.
  Deleting and re-cloning on a branch is different: the later Git merge's
  base still contains the old folder and can discard local-only files.
- `init` records no synced commit yet. The first push begins with the
  folder at `init`, not its earlier monorepo history, which may contain
  material never intended for publication
  ([example](../09-scenarios/02-starting-a-splice/04-init-new-upstream/01-removed-before-init/README.md)).

The command name `add` is avoided because it already means `git add`.

## Reuse Git's merge without joining histories

`git splice merge` combines fetched upstream changes with the current
folder as one ordinary monorepo commit. Upstream trees have the library
at their root; the monorepo has it under `<path>/`. They share no commit
ancestry, so the tool supplies a three-way merge base explicitly.

`reroot_tree` uses a temporary index to construct base and theirs in the
monorepo's layout, keeping everything outside the splice equal to `HEAD`:

<div align="center">

![Base, ours and theirs all retain HEAD's files outside the splice. Base uses the merge-base folder and old .splice; ours is HEAD; theirs uses the fetched upstream folder and records its commit. Cherry-picking theirs merges only the splice into one monorepo commit.](splicing-in.drawio.svg)

</div>

The temporary theirs commit has base as its parent. Running
`git cherry-pick theirs` then merges ours (`HEAD`) with theirs using that
base. Git's ort merge handles edits and renames; only the splice can
conflict, and its sync-point update travels with the files.

The ordinary merge base comes from R and T, not necessarily the commit
recorded in `.splice`. Rewritten upstream history can use the fetched
branch's fork point
([sync model](../03-concepts/02-sync-model.md#how-r-and-t-determine-the-status)).
The temporary commits gain no lasting refs; the fetched upstream history
stays separate from the monorepo's ancestry.

### The same files, another history

Matching files do not always mean no commit is needed. If upstream
rewrote or squash-merged the published history, or accepted an edited
rebuild, a pull must record that upstream commit even when only `.splice`
changes. Otherwise a later rebuild can publish the original commits again
([rewritten history](../09-scenarios/06-rewritten-history/02-upstream-rewritten-equal-tree/README.md),
[edited rebuild](../09-scenarios/06-rewritten-history/01-edited-before-push/README.md)).
After an ordinary push, R already equals T and no recording commit is needed.

### Conflicts and nested splices

Using a Git cherry-pick also leaves conflicts in a familiar, recoverable
state instead of requiring a separate recovery protocol. The command must
name the available recovery actions when it stops; their usage belongs in
[conflicts](../06-command-reference/05-pull.md#conflicts).

An outer pull can change the inner `.splice` files. For that reason,
merges run top-down and pulls also fetch the splices below, including
ones the pull introduces. Fetching them makes their newly recorded
commits available; pulling them is a separate choice. `pull --recursive`
also pulls the descendants and folds the result into one commit
([recursive pull](../06-command-reference/05-pull.md#--recursive)).

A failed fetch blocks dependent pulls above and below it; a failed merge
blocks merges below it. Pushes run bottom-up, so an outer push cannot
publish a nested sync point whose upstream commit has not been published.
A failed inner push blocks pushes above it.
