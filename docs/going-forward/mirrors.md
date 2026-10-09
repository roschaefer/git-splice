# Mirrors

Two folders with the same splice `id` are one splice in two places, so
they're meant to be **mirrors**: the same files, synced with the same
upstream. Folders with different ids are independent, even of one
upstream, e.g. a library at two versions
([splice identity](../../test/concepts/splice-identity/README.md#what-an-id-is)).
A mirror whose files differ from the others' has **drifted**.

git splice doesn't act on that yet: each splice is pulled and pushed on
its own, and compared only with its own upstream. This page says what
mirrors would need, what of it is possible, and what can be done
meanwhile.

## Where mirrors come from

- **A copy** in the monorepo, e.g. `cp -r vendor/a vendor/a-copy`.
- **One nested splice, reached twice.** If B's upstream splices in A,
  which has L nested, then a monorepo that splices in both A and B has
  `a/l` and `b/a/l`, with the same id: A's clone of L. The monorepo copied
  nothing.

Not from separate clones: if A, B and M each clone S, the three copies
have three ids, and are independent
([diamond](../../test/concepts/nesting/diamond.md)). To declare them
mirrors, a clone would need to take over the id of an existing splice.
There's no command for that yet.

Because of nesting, mirrors can't be forbidden or forced to stay alike:
`b/a/l` belongs to B's upstream, and may lag behind `a/l` because B has an
older version of A. The monorepo can't change that alone. Refusing
duplicate ids would refuse diamonds of that shape.

Nor can the rebuild tell mirrors apart. A splice's history starts where
a `.splice` with another id appears at its path, so when two mirrors
swap paths, each path keeps its own history: a push sends the commits
made at that path before the swap, though the folder has the other
mirror's files now, and may not have what those commits added
([example](../../test/concepts/splice-identity/README.md#mirrors-that-swap-paths)).

## What would be desired, and what's possible

| Desired | Status |
|---|---|
| Mirrors are stored once | **Already so.** Git stores identical files as one object, and identical folders as one tree ([diamond](../../test/concepts/nesting/diamond.md)). |
| A report of mirrors that drifted, with how to resolve it | **Possible**, not implemented: compare the folders of splices with the same id, without `.splice`. |
| A fork or a new version made from a copy is pointed out | **Possible** in part, not implemented: a copy that names another upstream than its mirrors. A new URL also keeps the id when the upstream moved, so it's a warning, not an error. |
| A pull of one mirror pulls the others | **Possible** for copies in the monorepo, not implemented. Not for a nested copy that another upstream owns. |
| Mirrors never differ | **Impossible.** Nested copies can differ for reasons the monorepo can't change. |
| Mirrors share one folder: an edit in one is an edit in all | **Impossible with Git.** A symlink commits a link, not files: A's own repository would get a link that points outside of it, and a checkout without symlink support gets a text file with the link's target. And a link is a reference: the copies could never differ, not even while you work. Mirrors are values, which are alike at sync points. |
| Mirrors take disk space once | **Impossible in Git's checkout**, which writes every file. A file system with copy-on-write, e.g. btrfs, XFS or APFS, can share the blocks of identical files that stay separate files. |

## Meanwhile: discipline

What git splice can't do yet, a team can do by hand. A report wouldn't
take that over, only point at it: it names the mirrors that differ and
how to resolve the difference. For a mirror that's only behind, that's a
plain `pull`, which anyone can check. Where both changed, the pull
merges, and the difference left is for someone to resolve. That fits the design's principles: refuse rather than
guess, and make the state explicit
([design](../design/README.md#principles)).

1. **Edit one copy**, e.g. the top-level `s/` in the
   [diamond](../../test/concepts/nesting/diamond.md).
2. **Push it, and pull every mirror right away**, as the diamond's round
   trip does.
3. **Compare mirrors** before merging, e.g. in CI. Their folders,
   without `.splice`, have the same tree:

   ```
   git diff --quiet HEAD:vendor/a HEAD:vendor/a-copy -- ':!.splice'
   ```

   ([splice identity](../../test/concepts/splice-identity/README.md#a-mirror-drifts)
   shows it with real output.)
4. **Clone, don't copy,** a fork or a version of its own, so it gets an
   id of its own
   ([splice identity](../../test/concepts/splice-identity/README.md#a-fork-is-a-splice-of-its-own)).
