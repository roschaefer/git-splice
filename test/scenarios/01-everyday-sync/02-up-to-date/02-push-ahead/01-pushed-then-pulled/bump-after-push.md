# Scenario: pushed-then-pulled: bump after the push

The same state as in [pushed-then-pulled](README.md): the monorepo pushed
a change, and `.splice` still names `seed`. A pull doesn't change that,
since the upstream branch is already part of the rebuild's history.

`git splice pull --bump`
([#115](https://github.com/roschaefer/git-splice/issues/115)) moves the
sync point up to the pushed commit anyway, in a commit that only changes
`.splice`, like a submodule bump. `pull` already writes such a commit
when the upstream has the folder's files under another history
([#92](https://github.com/roschaefer/git-splice/pull/92)). This shows what
the bump changes, and that it changes no commit a later push sends.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_pushed_then_pulled
```

## Without a bump

As in [pushed-then-pulled](README.md), a pull brings nothing in, and
`.splice` keeps naming `seed`. So the newest first-parent commit that
changed `.splice` is still the clone, and so is the boundary:

```scrut
$ git log --first-parent -1 --format=%s -- vendor/a/.splice
add vendor/a
```

Every rebuild walks the folder's commits since the boundary, and so
rebuilds the pushed commit again:

```scrut
$ boundary="$(git log --first-parent -1 --format=%H -- vendor/a/.splice)" &&
>   git log --first-parent --format=%s "$boundary"..HEAD -- vendor/a
local change
```

And the synced commits of the next two pulls span the push, which
misleads a bisect between them
([bisect into a pull](../../../../03-branches-and-teamwork/05-bisect-into-a-pull/01-after-a-push/README.md)).

## The bump

`--bump` writes the upstream branch as the synced commit, in a commit
that only changes `.splice`:

```scrut
$ git splice pull --bump vendor/a
ok   vendor/a fetched
ok   vendor/a: bumped the synced commit to e859a6b
```

```scrut
$ git show --stat --format=%s
splice: bump vendor/a from main at e859a6b

 vendor/a/.splice | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```

```scrut
$ git log -1 --format='%h %s' "$(git config --file vendor/a/.splice splice.commit)"
e859a6b local change
```

```scrut
$ git log --first-parent -1 --format=%s -- vendor/a/.splice
splice: bump vendor/a from main at e859a6b
```

The folder has the pushed commit's files, so the rebuild now starts at the
pushed commit itself, with nothing to walk:

```scrut
$ boundary="$(git log --first-parent -1 --format=%H -- vendor/a/.splice)" &&
>   git log --first-parent --format=%s "$boundary"..HEAD -- vendor/a
```

```scrut
$ git splice status
On branch main

  up to date  vendor/a
```

## A later push sends the same commit

The same change as in
[pushed-then-changed](01-pushed-then-changed/README.md), which made no bump:

```scrut
$ echo "later change" >>vendor/a/file.txt && git commit -q -a -m "later change"
```

```scrut
$ git splice log
===  vendor/a (main)
< 8b60a90 later change  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 8b60a90 to main
```

It's `8b60a90` with and without the bump: the rebuild before the bump
already had the pushed commit as the parent of what came next. So a
branch that never saw the bump pushes the same commits.

A bump merged the other way, from a feature branch into `main`, can
leave `main`'s `.splice` naming a commit the upstream deleted
([merged first](../../../../../walkthrough/bump.md#merged-first-a-commit-that-disappears)).

## A bump while ahead

A bump that comes after an unpushed commit keeps that commit. The bump's
folder differs from the synced commit it records, so it isn't the new
boundary: the rebuild still starts before it, and continues from there:

```scrut
$ echo "unpushed change" >>vendor/a/file.txt && git commit -q -a -m "unpushed change"
```

```scrut
$ git splice log
===  vendor/a (main)
< ea43c10 unpushed change  (Test <test@example.com>)
```

```scrut
$ git splice pull --bump vendor/a
ok   vendor/a fetched
ok   vendor/a: bumped the synced commit to 8b60a90
```

```scrut
$ git splice status
On branch main

  ahead 1  vendor/a
```

```scrut
$ git splice log
===  vendor/a (main)
< ea43c10 unpushed change  (Test <test@example.com>)
```

It's `ea43c10` before and after the bump. That bump is safe, but it
saves the rebuild nothing: the boundary is still the clone. Bumping pays off right after a push, when the folder has the
upstream branch's files.
