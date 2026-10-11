# Scenario: pushed-then-pulled: bump after the push

The same state as in [pushed-then-pulled](README.md): the monorepo pushed
a change, and `.splice` still names `seed`. A pull doesn't change that,
since the upstream branch is already part of the rebuild's history.

`git splice pull --bump`
([#115](https://github.com/roschaefer/git-splice/issues/115)) would move
the sync point up to the pushed commit anyway, in a commit that only
changes `.splice`, like a submodule bump. `pull` already writes such a
commit when the upstream has the folder's files under another history
([#92](https://github.com/roschaefer/git-splice/pull/92)). There's no
such option yet, so here the bump is made by hand. It shows what the bump
changes, and that it changes no commit a later push sends.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_pushed_then_pulled
```

## Without a bump

The pull brings nothing in, and `.splice` keeps naming `seed`:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: nothing to pull
```

```scrut
$ git log -1 --format='%h %s' "$(git config --file vendor/a/.splice splice.commit)"
bde4164 seed
```

So the boundary, the newest first-parent commit that changed `.splice`,
is still the clone:

```scrut
$ git log --first-parent -1 --format=%s -- vendor/a/.splice
add vendor/a
```

Every rebuild walks the folder's commits since the boundary, and so
rebuilds the pushed commit again:

```scrut
$ git log --first-parent --format=%s "$(git log --first-parent -1 --format=%H -- vendor/a/.splice)"..HEAD -- vendor/a
local change
```

And the synced commits of the next two pulls span the push, which
misleads a bisect between them
([bisect into a pull](../../../bisect-into-a-pull/after-a-push/README.md)).

## The bump, by hand

What `--bump` would write: the upstream branch as the synced commit,
in a commit that only changes `.splice`, with a message like a pull's:

```scrut
$ U="$(git -C "$UPSTREAM" rev-parse main)" && git config --file vendor/a/.splice splice.commit "$U" && git commit -q -m "splice: bump vendor/a from main at ${U:0:7}" -- vendor/a/.splice
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
$ git log --first-parent --format=%s "$(git log --first-parent -1 --format=%H -- vendor/a/.splice)"..HEAD -- vendor/a
```

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```

## A later push sends the same commit

The same change as in
[pushed-then-changed](pushed-then-changed/README.md), which made no bump:

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
([bump-on-a-branch](bump-on-a-branch.md)).

## A bump while ahead

A bump that comes after an unpushed commit keeps that commit. When the
boundary's folder differs from the synced commit, the rebuild also
rebuilds the history before the boundary, and continues from there:

```scrut
$ echo "unpushed change" >>vendor/a/file.txt && git commit -q -a -m "unpushed change"
```

```scrut
$ git splice log
===  vendor/a (main)
< ea43c10 unpushed change  (Test <test@example.com>)
```

```scrut
$ U="$(git -C "$UPSTREAM" rev-parse main)" && git config --file vendor/a/.splice splice.commit "$U" && git commit -q -m "splice: bump vendor/a from main at ${U:0:7}" -- vendor/a/.splice
```

```scrut
$ git splice status
ok   vendor/a -> main (push: ahead 1)
```

```scrut
$ git splice log
===  vendor/a (main)
< ea43c10 unpushed change  (Test <test@example.com>)
```

It's `ea43c10` before and after the bump. That bump is safe, but it
saves the rebuild nothing: the walk still starts at the previous
boundary. Bumping pays off right after a push, when the folder has the
upstream branch's files.
