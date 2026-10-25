# What you don't want: the old commits back on the PR

In the [same state](README.md), `feature` is rebased in the monorepo,
and then the PR, which was never rebased, is pulled. That mixes the two
strategies: the next push sends the old commits back to the PR, next to
the rebased ones.

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

The rebase copies *b* onto *p* as *c*:

```scrut
$ git rebase -q main
```

Every commit only upstream has, *f*, is a copy of one `feature` has
now, so `push` suggests `--force`, not the usual `pull`:

```scrut
$ git splice push vendor/a
!!   vendor/a: upstream's 'feature' has only copies of commits this branch has, e.g. from before a 'git rebase' here -- run 'git splice push --force vendor/a' to replace them: a pull would keep both
!!   Failed: vendor/a
[1]
```

`pull --rebase` would take *f* in as it is and drop *m*: *f* lacks it,
since `main` brought it in, not `feature`. It refuses, and prints the
two strategies:

```scrut
$ git splice pull --rebase vendor/a
ok   vendor/a fetched
!!   vendor/a: 'feature' lacks the synced commit 5cc5467, which this branch got from 'main' -- --rebase would drop it. To rebase 'feature' onto 'main', do it on one side only:

  # keep this branch's rebase, overwriting upstream's 'feature':
  git splice push --force -- vendor/a

  # OR: rebase or merge 'feature' onto 'main' upstream, e.g. with "Update branch" on GitHub, then:
  git splice pull -- vendor/a

!!   Failed: vendor/a
[1]
```

A plain `pull` goes through. It merges *f*, the copy of the feature
change from before the rebase, into `feature` as the pull *x*. No
change is lost, and `lock.txt` stays:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled a35a3ef
```

```scrut
$ cat vendor/a/lock.txt
bump dep
```

But the push then sends both copies of the feature change, the rebased
*c'* and the old *f*, joined by *x'*, the copy of the pull:

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed c08925d to feature
```

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s feature
*   splice: pull vendor/a from feature at a35a3ef
|\  
| * feature change
* | feature change
* | bump dep
|/  
* seed
```

<div align="center">

![The monorepo, a, p on main, c and the pull x on feature, with H at x; upstream, k with two children, m on main and f, which is U(H); c prime on top of m; x prime merges c prime and f, and is T, R and feature](pulled-and-pushed.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/pulled-and-pushed.drawio.svg" \
>   a=HEAD~3 p=main c=HEAD~1 x=HEAD k=refs/splices/a/heads/main~1 \
>   m=refs/splices/a/heads/main f="$f"
ok   pulled-and-pushed.drawio.svg: 9 commits, 13 arrows, 5 boxes, 1 lanes
```
-->

The PR lists `feature change` twice, and the merge between them. A
squash merge of the PR hides that; a rebase merge puts both copies on
`main`.

## If it happened

Before anyone else builds on the PR, drop the pull, and go on with
[strategy 1](monorepo-first.md): push the rebased branch with
`--force`. `--keep` refuses if that would lose uncommitted changes:

```scrut
$ git reset -q --keep HEAD~1
```

```scrut
$ git splice push --force vendor/a
ok   vendor/a: pushed 8613e5d to feature
```

The PR ends up as strategy 1 leaves it: *m*, then the feature change
on top. The old copy *f* and the merge *x'* are on no branch any more:

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s feature
* feature change
* bump dep
* seed
```

<div align="center">

![The monorepo, a, p on main and c on feature, with H at c; upstream, k, m on main, which is U(H), and c prime on top of m, which is T, R and feature](pushed-with-force.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/pushed-with-force.drawio.svg" \
>   a=HEAD~2 p=main c=HEAD k=refs/splices/a/heads/main~1 \
>   m=refs/splices/a/heads/main
ok   pushed-with-force.drawio.svg: 6 commits, 8 arrows, 4 boxes, 1 lanes
```
-->
