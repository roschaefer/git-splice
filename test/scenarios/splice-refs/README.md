# Scenario: splice-refs

How everyday `git splice` commands change the refs a splice keeps in the
monorepo, and what those refs cost.

- **Monorepo**: one commit, no splice yet.
- **Upstream**: `main` with `seed`, and a branch `fix-parser`. The
  monorepo reaches it as `https://git.example.com/a.git`, which
  `url.<base>.insteadOf` maps to a bare repository next door.

## What a ref is

A ref is a name for a commit. Branches are refs under `refs/heads/`, tags
under `refs/tags/`, and `git fetch` keeps a remote's branches under
`refs/remotes/<remote>/`. These are only conventions: a ref can live under
any `refs/` path, and git-splice keeps each splice's upstream branches
under `refs/splices/<path>/`.

A ref costs one line in `.git/packed-refs`, or a small file. The commits it
names, and their trees and files, are what cost space.

## Output

`scenario_splice_refs` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_splice_refs
```
-->

Before the splice, the monorepo has only its own branch:

```scrut
$ git for-each-ref --format='%(objectname:short) %(refname)'
4d732bc refs/heads/main
```

### `clone` fetches every upstream branch

`clone` fetches all of the upstream's branches, not only the one it splices
in, each to a ref under the splice's path:

```scrut
$ git splice clone https://git.example.com/a.git vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned bde4164 from main
```

```scrut
$ git for-each-ref --format='%(objectname:short) %(refname)'
ac208c0 refs/heads/main
530decc refs/splices/vendor/a/fix-parser
bde4164 refs/splices/vendor/a/main
```

The upstream's commits now live in the monorepo's object store, with the
upstream's own layout: `file.txt` sits at the root, not under `vendor/a/`.
Any Git command can read them, by their short name too:

```scrut
$ git log --format='%h %s' splices/vendor/a/main
bde4164 seed
```

```scrut
$ git ls-tree -r --abbrev=7 --format='%(objectname) %(path)' splices/vendor/a/main
e31de1f file.txt
```

In the monorepo, the same file is spliced in under `vendor/a/`, next to
`.splice`. It has the same hash, so Git stores it once:

```scrut
$ git ls-tree -r --abbrev=7 --format='%(objectname) %(path)' HEAD
c1353c2 vendor/a/.splice
e31de1f vendor/a/file.txt
```

The upstream's history is not part of the monorepo's. The splice commit
names the upstream commit only in its message and in `.splice`:

```scrut
$ git log --format='%h %s'
ac208c0 splice: clone vendor/a from main at bde4164
4d732bc initial commit
```

```scrut
$ git merge-base --is-ancestor splices/vendor/a/main HEAD || echo "not an ancestor"
not an ancestor
```

### `fetch` moves the refs

Someone else pushes to the upstream's `main`.
[`seed_bare_repo`](../../helpers/fixtures.bash) does that: it clones the
upstream, appends a line to `file.txt`, commits and pushes. `fetch` moves
the ref, as `git fetch` moves a remote-tracking branch:

```scrut
$ seed_bare_repo "$UPSTREAM" "upstream change"
```

```scrut
$ git splice fetch
ok   vendor/a fetched (main moved bde4164..6045a98)
```

```scrut
$ git for-each-ref --format='%(objectname:short) %(refname)' refs/splices
530decc refs/splices/vendor/a/fix-parser
6045a98 refs/splices/vendor/a/main
```

`pull` is `fetch`, then `merge`. Its fetch moves and prunes refs like the
one above, here with nothing new to fetch. Its merge moves no splice ref;
it writes a monorepo commit:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled 6045a98
```

### `push` moves the ref it pushed to

A local change, pushed. Pushing to a URL updates no ref by itself, so
`push` records what the upstream has now:

```scrut
$ echo "local change" >>vendor/a/file.txt && git commit -q -a -m "local change"
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed eda2ac7 to main
```

```scrut
$ git for-each-ref --format='%(objectname:short) %(subject) %(refname)' refs/splices
530decc parser fix refs/splices/vendor/a/fix-parser
eda2ac7 local change refs/splices/vendor/a/main
```

### A monorepo branch syncs with the upstream branch of the same name

On a monorepo branch named `fix-parser`, the splice syncs with
`splices/vendor/a/fix-parser`. It's diverged: the upstream's `fix-parser`
has the parser fix, and this branch has the changes made on `main`:

```scrut
$ git switch -q -c fix-parser main
```

```scrut
$ git splice status
ok   vendor/a -> fix-parser (diverged: ahead 2, behind 1)
```

On a new branch, `push` creates the upstream branch, and with it a new ref:

```scrut
$ git switch -q -c rename-helper main
```

```scrut
$ echo "rename helper" >>vendor/a/file.txt && git commit -q -a -m "rename helper"
```

```scrut
$ git splice push vendor/a
??   vendor/a: upstream has no 'rename-helper' branch yet -- this push creates it (changed since 'main')
ok   vendor/a: pushed af0b42b to rename-helper
```

```scrut
$ git for-each-ref --format='%(refname)' refs/splices
refs/splices/vendor/a/fix-parser
refs/splices/vendor/a/main
refs/splices/vendor/a/rename-helper
```

### `fetch` prunes refs of deleted branches

The upstream deletes `fix-parser`, e.g. after merging it. `fetch` removes
its ref, as `git fetch --prune` does:

```scrut
$ fix_parser="$(git rev-parse splices/vendor/a/fix-parser)"
```

```scrut
$ git -C "$UPSTREAM" branch -q -D fix-parser
```

```scrut
$ git splice fetch
ok   vendor/a fetched
```

```scrut
$ git for-each-ref --format='%(refname)' refs/splices
refs/splices/vendor/a/main
refs/splices/vendor/a/rename-helper
```

The commit the ref named is still in the object store, but nothing points
at it anymore. `git gc` deletes such commits, by default once they're two
weeks old, counted from when the object was written, not from when the
ref was deleted; `--prune=now` doesn't wait.

By default, these refs keep no reflog (unless `core.logAllRefUpdates` is
`always`). A branch's or remote-tracking branch's reflog
keeps a commit it moved away from for another 30 days
(`gc.reflogExpireUnreachable`), so that matters when a fetch moves a
splice's ref after a force push upstream. A deleted ref's reflog is
deleted with it, so here it makes no difference:

```scrut
$ git cat-file -t "$fix_parser"
commit
```

```scrut
$ git gc --quiet --prune=now && git cat-file -t "$fix_parser"
fatal: git cat-file: could not get object info
[128]
```

### A clone of the monorepo has no splice refs

By default, `git push` and `git clone` only transfer branches and tags,
and the commits those reach. (`--mirror`, or an explicit refspec, would
transfer `refs/splices/*` too.) A clone of the monorepo has every `.splice` file, but
none of the refs and none of the upstream's commits. Its splices are never
fetched until it fetches them. (`--no-local` makes the clone go through
Git's transport, as a clone from a server does. A clone from a local path
would copy every object.)

```scrut
$ git switch -q main && git clone -q --no-local . ../clone && git -C ../clone for-each-ref --format='%(refname)'
refs/heads/main
refs/remotes/origin/HEAD
refs/remotes/origin/fix-parser
refs/remotes/origin/main
refs/remotes/origin/rename-helper
```

```scrut
$ cd ../clone && git splice status; cd - >/dev/null
??   vendor/a -> main (never fetched -- run 'git splice fetch vendor/a')
```

### `git mv` leaves the refs under the old path

The refs are named after the splice's path, and moving the folder doesn't
rename them. Until the next fetch, the moved splice has no refs, and
`status` wrongly says the upstream has no such branch
([#21](https://github.com/roschaefer/git-splice/issues/21)):

```scrut
$ mkdir libs && git mv vendor/a libs/a && git commit -q -m "move a"
```

```scrut
$ git splice status
??   libs/a -> main (upstream has no such branch -- push would create it)
```

A fetch creates refs under the new path. The old ones stay behind, pointing
at the same commits:

```scrut
$ git splice fetch
ok   libs/a fetched
```

```scrut
$ git for-each-ref --format='%(objectname:short) %(refname)' refs/splices
eda2ac7 refs/splices/libs/a/main
af0b42b refs/splices/libs/a/rename-helper
eda2ac7 refs/splices/vendor/a/main
af0b42b refs/splices/vendor/a/rename-helper
```

They cost no extra space, since the new refs keep the same commits alive.
Deleting them is safe on this branch:

```scrut
$ git for-each-ref --format='delete %(refname)' refs/splices/vendor/a/ | git update-ref --stdin
```

```scrut
$ git for-each-ref --format='%(refname)' refs/splices
refs/splices/libs/a/main
refs/splices/libs/a/rename-helper
```

But other branches may still have the splice at the old path. On those,
it now has no refs, as right after the move:

```scrut
$ git switch -q rename-helper && git splice status
ok   vendor/a -> rename-helper (upstream has no such branch; ahead 4 since 'main' -- push would create it)
```

A fetch there brings them back, under the old path:

```scrut
$ git splice fetch && git splice status
ok   vendor/a fetched
ok   vendor/a -> rename-helper (up to date)
```

## Lifetime, space and garbage collection

- **Lifetime.** A ref lives until something deletes it. `fetch` overwrites a
  splice's refs and deletes the refs of branches the upstream no longer
  has; `push` updates the ref it pushed to. Nothing deletes the refs of a
  splice that was moved or removed.
- **Space.** Refs cost next to nothing; objects cost the space. Because
  Git addresses objects by content, files the monorepo and the upstream
  share are stored once. What a splice adds is the upstream's commits and
  trees, and old versions of files the monorepo never had.
- **Garbage collection.** Refs, reflogs and the index are where `git gc`
  starts looking for what to keep. A commit only a deleted ref named
  becomes garbage. More refs mean more starting points, but the walk stops
  at commits it has seen, so its cost depends on the number of objects,
  not refs. Refs only slow Git down by the tens of thousands, and `gc`
  packs them into one file. A splice has one ref per upstream branch, and
  pruning keeps that number small.
