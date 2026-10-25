# Strategy 2: rebase upstream first

In the [same state](README.md), `feature` is rebased onto `main`
upstream, and the monorepo pulls the result. The monorepo's `feature`
isn't rebased:

1. Upstream: rebase `feature` onto `main`, e.g. with "Update branch" on
   GitHub. Here, it's a rebase in a clone of the upstream.
2. On `feature`: `git splice pull`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_feature_branch_behind_default_branch
```

<!--
```scrut
$ f="$(git rev-parse splices/a/heads/feature)"
```
-->

The rebase copies *f* onto *m* as *f'*:

```scrut
$ git clone -q -b feature "$UPSTREAM" ../pr &&
>   git -C ../pr -c user.name=Maintainer -c user.email=maintainer@example.com \
>     rebase -q origin/main &&
>   git -C ../pr push -q --force origin feature
```

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s feature
* feature change
* bump dep
* seed
```

The pull brings *m* into `feature` as *x*, and records *f'* as the
synced commit:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (feature moved a35a3ef..e724c1a)
ok   vendor/a: pulled e724c1a
```

```scrut
$ cat vendor/a/lock.txt
bump dep
```

<div align="center">

![The monorepo, a with two children, p on main and b, then the pull x on feature, which is H; upstream, k, m on main, and f prime on top of m, which is T, R, U(H) and feature](pulled-the-rebased-pr.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/pulled-the-rebased-pr.drawio.svg" \
>   a=HEAD~2 b=HEAD~1 x=HEAD p=main k=refs/splices/a/heads/main~1 \
>   m=refs/splices/a/heads/main f="$f"
ok   pulled-the-rebased-pr.drawio.svg: 7 commits, 9 arrows, 4 boxes, 1 lanes
```
-->

The monorepo's `feature` keeps *b*, and the pull *x* on top of it: a
rebase upstream doesn't rewrite the monorepo's history. Nothing is left
to push:

```scrut
$ git splice status
On branch feature

  up to date  vendor/a
```

The same goes for "Update branch" with a merge: the pull brings the
merge in, and records it as the synced commit.
