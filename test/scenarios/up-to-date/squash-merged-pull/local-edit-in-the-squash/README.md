# Scenario: local-edit-in-the-squash

The [parent scenario's](../README.md) squash merge, but the feature
branch also edited the folder. So one commit does two things: it records
the pulled upstream commit in `.splice`, and it holds a local edit that
the upstream doesn't have.

- **Upstream**: `seed` on `main`, and someone else's commit on `feature`.
- **Monorepo (`vendor/a/`)**: cloned at `seed`. On `feature`,
  `git splice pull` brought in the upstream commit, then a commit added
  `local.txt`. `feature` was squash-merged into `main` and deleted.

<div align="center">

![The monorepo's a and the squash merge s; the upstream's k and f; B is a, and R is s prime on top of f](local-edit-in-the-squash.drawio.svg)

</div>

The drawing names the monorepo's commits a (`add vendor/a`) and s (the
squash merge), and the upstream's k (`seed`, T) and f
(`upstream feature work`). s records U(H) = f, but B is a, so R copies s
onto f. T lacks f and s', so they're dashed.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_local_edit_in_the_squash
```

The drawing shows what Git and `git-splice` say about it, with each
commit named by its place in the history
([`check_drawing`](../../../../helpers/drawing.bash)):

```scrut
$ check_drawing "$TESTDIR/local-edit-in-the-squash.drawio.svg" a=HEAD~1 s=HEAD k=refs/splices/upstream/main f=refs/splices/upstream/feature
ok   local-edit-in-the-squash.drawio.svg: 5 commits, 8 arrows, 5 boxes, 0 frames
```

The squash merge is the last commit, and the only one since the clone:

```scrut
$ git log --format=%s
feature (squash-merged)
add vendor/a
initial commit
```

### What the squash merge records, and what it holds

Its `.splice` records the pulled commit, U(H):

```scrut
$ git -C "$UPSTREAM" log -1 --format=%s "$(git config --file vendor/a/.splice splice.commit)"
upstream feature work
```

But its folder isn't that commit: it has the local edit too.

```scrut
$ git diff --name-only "$(git config --file vendor/a/.splice splice.commit)" HEAD:vendor/a -- ':!.splice'
local.txt
```

### Where the rebuild starts

So the squash merge can't be B, the newest commit that changed
`.splice` and whose folder is the commit it recorded
([sync model](../../../../concepts/sync-model/README.md)). The rebuild
copies it, and starts where it would have before the squash merge, at
the clone:

```scrut
$ git log -1 --format=%s "$(git splice boundary vendor/a)"
add vendor/a
```

The rebuild copies the commits after B:

```scrut
$ git log --format=%s "$(git splice boundary vendor/a)..HEAD" -- vendor/a
feature (squash-merged)
```

R is that copy, on top of the pulled commit:

```scrut
$ git log --format=%s "$(git splice rebuild vendor/a)"
feature (squash-merged)
upstream feature work
seed
```

Before, B was the squash merge itself, because its `.splice` changed.
Then `git log B..HEAD` was empty, while a push still sent the local edit.

### Push

The upstream's `main` gets both: the feature work, and the local edit,
under the squash merge's message.

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 0461d52 to main
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
feature (squash-merged)
upstream feature work
seed
```
