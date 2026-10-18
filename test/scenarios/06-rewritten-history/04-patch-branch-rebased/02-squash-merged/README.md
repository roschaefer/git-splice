# Scenario: squash-merged

The [same rebased branch](../README.md), taken into a protected `main`:
changes reach it only through pull requests, which are squash-merged.
This page goes there step by step, with a drawing after each.

- **Monorepo (`vendor/a/`)**: *a* (`add vendor/a`) cloned *p*, and
  follows `patches` on `main`.
- **Upstream**: *k* (`seed`), then `patches` rebased from *p*
  (`patch`) onto *m* (`patch, reworded upstream`).

## 1. Pull on a local `main`

A pull request's branch can't pull `patches`: it syncs with the upstream
branch named like it, and the upstream has none. So the pull happens on
a local `main`. It makes *c* (`splice: pull vendor/a from patches at
m`), which records *m*. The folder has exactly *m*'s files, so R is *m*,
and *p* stays dropped:

<div align="center">

![Monorepo a and c; c records m; R is m; p, the old patch, is dashed](pulled-on-main.drawio.svg)

</div>

## 2. Move it to a pull request

`main` is protected, so *c* moves to a pull request's branch,
`take-the-release`, and a local change goes on top, *b* (`local
change`). On this branch, R is *b'* on top of *m*: linear, just right.

<div align="center">

![Monorepo a, c and b on the pull request's branch; R is b prime on top of m](pull-request.drawio.svg)

</div>

## 3. Squash-merge it

The squash merge puts *c* and *b* into one commit on `main`, *s*
(`vendor/a: take the release, and a local change (#1)`). It records
*m*, but its folder is *m*'s plus `local.txt`.

<div align="center">

![The monorepo's a and s; R is s prime, a merge of p, the old patch, and m, the reworded one](squash-merged.drawio.svg)

</div>

R is now *s'*, a merge of *p* and *m*: the next push publishes *p*
again, the patch the upstream dropped. On `main`, *c* is gone, so B,
where the rebuild starts, is still *a*, and the rebuild starts at U(B),
*p*. At *s*, it joins in U(H), *m*, as a merge: *s*'s folder isn't
*m*'s, so it can't start over at *m* alone.

## To decide

1. **Which upstream branch a pull request's branch pulls.** Today, the
   one named like it, or nothing (step 1). Taking the one `main` follows
   when the upstream has none would let the pull happen on the pull
   request's branch, where `pull --rebase` could rewrite it.
2. **What the rebuild makes of *s*.** *s* records *m*, which doesn't
   contain *p*, the synced commit before it: the upstream rewrote its
   branch between the two. A rule that the monorepo's history alone
   decides: at such a commit, the rebuild starts at its synced commit
   and copies the commit on top of it, without what came before. R would
   be *s'* on top of *m*, as in step 2, and *p* would stay dropped:

   <div align="center">

   ![Proposed: R is s prime on top of m alone; p stays dropped](squash-merged-proposed.drawio.svg)

   </div>

   This drawing shows the proposal, not what the code does, so nothing
   checks it. Unpushed changes before *s* would stay in *s'*'s files, but
   not as commits of their own.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds the [rebased branch](../README.md):

```scrut
$ build_scenario scenario_squash_merged
```

```scrut
$ p="$(git config --file vendor/a/.splice splice.commit)"
```

### 1. Pull on a local `main`

On a pull request's branch, there's nothing to pull:

```scrut
$ git switch -q -c another-pull-request && git splice pull vendor/a; git switch -q main
ok   vendor/a fetched
ok   vendor/a: upstream has no 'another-pull-request' branch -- nothing to pull
```

On `main`, there is:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled 97171d6
```

```scrut
$ check_drawing "$TESTDIR/pulled-on-main.drawio.svg" a=HEAD~1 c=HEAD k="$p~1" p="$p" m=refs/splices/upstream/patches
ok   pulled-on-main.drawio.svg: 5 commits, 6 arrows, 3 boxes, 1 lanes
```

### 2. Move it to a pull request

```scrut
$ git switch -q -c take-the-release && git switch -q main && git reset -q --hard HEAD~1 && git switch -q take-the-release
```

```scrut
$ echo "local change" >vendor/a/local.txt && git add vendor/a/local.txt && git commit -q -m "local change"
```

```scrut
$ check_drawing "$TESTDIR/pull-request.drawio.svg" a=HEAD~2 c=HEAD~1 b=HEAD k="$p~1" p="$p" m=refs/splices/upstream/patches
ok   pull-request.drawio.svg: 7 commits, 11 arrows, 6 boxes, 1 lanes
```

```scrut
$ git log --format=%s "$(git splice rebuild vendor/a)"
local change
patch, reworded upstream
seed
```

### 3. Squash-merge it

```scrut
$ git switch -q main && git merge -q --squash take-the-release >/dev/null && git commit -q -m "vendor/a: take the release, and a local change (#1)"
```

```scrut
$ git log --format=%s
vendor/a: take the release, and a local change (#1)
add vendor/a
initial commit
```

```scrut
$ check_drawing "$TESTDIR/squash-merged.drawio.svg" a=HEAD~1 s=HEAD k="$p~1" p="$p" m=refs/splices/upstream/patches
ok   squash-merged.drawio.svg: 6 commits, 10 arrows, 5 boxes, 1 lanes
```

```scrut
$ git splice status
On branch main

  ahead 2  vendor/a -> patches
```

R joins *p* in again:

```scrut
$ git log --graph --format=%s "$(git splice rebuild vendor/a)"
*   vendor/a: take the release, and a local change (#1)
|\  
| * patch, reworded upstream
* | patch
|/  
* seed
```
