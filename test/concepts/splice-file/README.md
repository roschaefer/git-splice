# The `.splice` file

A folder is a splice because it has a `.splice` file, committed like any
other file. It names the upstream, and the upstream commit the folder
last matched, the synced commit U(H) of the
[sync model](../sync-model/README.md). That's all the state there is: a
clone of the monorepo has every splice, with nothing to set up.

```text
[splice]
	id = 9b2e41c07d5a8f36       # which splice this is, wherever it moves
	commit = 3f1c…              # the synced commit U(H)
[upstream "origin"]
	url = git@github.com:x/a.git
	default-branch = master     # only if it's named differently, see below
```

- **It's in Git's config format**, so `git config --file` reads and
  writes it. It looks like TOML, but isn't. A `.splice` that `git config`
  can't parse, e.g. one committed with conflict markers, stops every
  command with Git's message.
- **Only a committed one counts.** Commands find splices by every
  `*/.splice` in `HEAD`, at any depth. A staged `.splice` isn't a splice
  yet.
- **`clone` and `init` create it, `merge` and `pull` update it.** `push`
  never changes the monorepo, so it never writes `.splice`.
- **It stores no path and no monorepo commit.** The folder that contains
  it is the splice, so it moves along with `git mv`, and rebases or
  squash merges in the monorepo can't invalidate it.
- **Its own upstream never gets it.** A push leaves it out of every
  commit it sends. The `.splice` of a [nested](../nesting/README.md)
  splice is content of the splice above, whose push sends it.
- **Its `id` names the splice**, not an upstream: it stays the same when
  the folder moves or the upstream's URL changes
  ([splice identity](../splice-identity/README.md)). Commands refuse a
  `.splice` without one.
- **Its upstreams are named**, like Git remotes, so a splice can follow
  several, e.g. a company fork and the original
  ([upstreams](../upstreams/README.md)). `clone` and `init` name theirs
  `origin`.
- **Without `default-branch`**, an upstream's default branch is named
  like the monorepo's, or, for a nested splice, like the splice above's
  ([nested-default-branch](../../scenarios/05-nested-splices/02-nested-default-branch/README.md)).
  `clone` and `init` record it only where it differs, e.g. when `main`
  syncs with `master`
  ([default-branch](../../scenarios/04-upstreams/01-default-branch/README.md)). If the
  splice above has several upstreams with different default branches and
  no `default-upstream`, commands refuse
  ([example](../../scenarios/05-nested-splices/01-nested-splices/01-outer-fork/fork-default-branch-below.md)).
- **Two branches that both pulled conflict in it** when they're merged.
  Resolve it by keeping the newer synced commit
  ([concurrent-pulls](../../scenarios/03-branches-and-teamwork/04-concurrent-pulls/README.md)).

The [design](../../../docs/design/README.md#the-splice-file) explains
each of these choices.

## Output

The walkthrough's [sandbox](../../../docs/sandbox.md), where
`vendor/pkg-a/` is behind its upstream by one commit.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../walkthrough/scrut-setup.sh"
```
-->

```scrut
$ cat vendor/pkg-a/.splice
[splice]
\tid = 679c78b9916de804 (escaped)
\tcommit = 9bb866a3ba726f2229597a45e8ea3368f7e669a8 (escaped)
[upstream "origin"]
\turl = https://git.example.com/pkg-a.git (escaped)
```

`git config` reads it like any config file:

```scrut
$ git config --file vendor/pkg-a/.splice splice.commit
9bb866a3ba726f2229597a45e8ea3368f7e669a8
```

There's no Git remote, so nothing can push the monorepo to an upstream by
mistake:

```scrut
$ git remote
```

A pull records the new synced commit:

```scrut
$ git splice pull vendor/pkg-a >/dev/null && git show --format=%s -- vendor/pkg-a/.splice
splice: pull vendor/pkg-a from main at 703b936

diff --git a/vendor/pkg-a/.splice b/vendor/pkg-a/.splice
index 16b61ae..5635a7f 100644
--- a/vendor/pkg-a/.splice
+++ b/vendor/pkg-a/.splice
@@ -1,5 +1,5 @@
 [splice]
 \tid = 679c78b9916de804 (escaped)
-\tcommit = 9bb866a3ba726f2229597a45e8ea3368f7e669a8 (escaped)
+\tcommit = 703b9360f7ac335a1134e9b5771a90a7c09ba39a (escaped)
 [upstream "origin"]
 \turl = https://git.example.com/pkg-a.git (escaped)
```

A push sends the folder's files, without `.splice`:

```scrut
$ echo "a local fix" >>vendor/pkg-a/file.txt &&
>   git commit -qam "pkg-a: a local fix" &&
>   git splice push vendor/pkg-a >/dev/null
```

```scrut
$ ls -A vendor/pkg-a
.splice
file.txt
```

```scrut
$ git ls-tree --name-only splices/pkg-a/heads/main
file.txt
```
