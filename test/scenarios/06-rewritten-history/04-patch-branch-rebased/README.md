# Scenario: patch-branch-rebased

A fork carries patches of its own on a branch, `patches`, on top of the
upstream's `main`, and the monorepo's `main` follows that branch
instead of the upstream's `main`. When the upstream releases, the fork
rebases `patches` onto the new `main`. Patches the upstream took drop
out, the others get new commits. Either way, the commit the monorepo
synced last is on no upstream branch any more
([#169](https://github.com/roschaefer/git-splice/issues/169)).

- **Monorepo (`vendor/a/`)**: *a* (`add vendor/a`) cloned *p* from
  `patches`, and follows `patches` on `main`.
- **Upstream**: *k* (`seed`) on `main`, and *p* (`patch`) on top of it
  on `patches`. Then `main` takes the patch reworded, *m* (`patch,
  reworded upstream`), and `patches` is rebased onto it: the patch drops
  out, so `patches` is *m* too. Already fetched.

<div align="center">

![The monorepo's a records p, the old patch on top of k; T is m, the reworded patch on top of k](patch-branch-rebased.drawio.svg)

</div>

U(H) is *p*, but T is *m*, and no upstream branch has *p* any more, so
it's dashed. Git's merge base of the two is *k*, from before the patch:
merging from there, the patch and its rewording would be changes on
both sides, and conflict. A `pull` merges from U(H) instead, the files
the monorepo took last, so the upstream's new version simply replaces
them.

That's only safe as long as everything the monorepo changed in the
folder is pushed, so the rebased branch has it. An [unpushed local
commit](01-unpushed-local-commit/README.md) is a different story.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_patch_branch_rebased
```

On the monorepo's default branch, a splice syncs with its upstream's
`default-branch`. Setting it to the fork's patch branch makes `main`
follow that branch, for `pull`, `push` and `status` alike:

```scrut
$ git config --file vendor/a/.splice --list
splice.commit=2aff4fd3680b50c26e359216c93491b6a1b039b6
splice.id=[0-9a-f]{16} (regex)
upstream.origin.url=$UPSTREAM
upstream.origin.default-branch=patches
```

The drawing shows what Git and `git-splice` say about it, with each
commit named by its place in the history
([`check_drawing`](../../../../check-drawing/)):

```scrut
$ p="$(git config --file vendor/a/.splice splice.commit)"
```

```scrut
$ check_drawing "$TESTDIR/patch-branch-rebased.drawio.svg" a=HEAD k="$p~1" p="$p" m=refs/splices/upstream/patches
ok   patch-branch-rebased.drawio.svg: 4 commits, 5 arrows, 3 boxes, 1 lanes
```

```scrut
$ git -C "$UPSTREAM" log --format=%s patches
patch, reworded upstream
seed
```

```scrut
$ git splice status
On branch main

  ahead 1, behind 1  vendor/a -> patches
```

`ahead 1` is *p*: the rebased branch lacks it, though the monorepo has
nothing to push. That count is misleading after a rewrite upstream.

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled 97171d6
```

The folder has the upstream's version of the patch, and nothing else
changed:

```scrut
$ cat vendor/a/file.txt
seed
patch, reworded upstream
```

```scrut
$ git splice status
On branch main

  up to date  vendor/a -> patches
```

R, what a push would send, is the upstream's branch itself: the old
patch, *p*, doesn't come back.

```scrut
$ [ "$(git splice rebuild vendor/a)" = "$(git rev-parse refs/splices/upstream/patches)" ] && echo "R is T"
R is T
```
