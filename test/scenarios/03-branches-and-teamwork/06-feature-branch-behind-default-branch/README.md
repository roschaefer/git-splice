# Scenario: feature-branch-behind-default-branch

A feature branch was pushed, so upstream has it as a PR. Then upstream's
`main` moved on, the monorepo's `main` pulled that in, and the feature
branch was rebased onto `main` with plain `git rebase main`, to bring the
PR up to date.

- **Upstream**: *k* (`seed`) on `main`, then *m* (`bump dep`), which adds
  `lock.txt`. `feature`, the PR, is *f* (`feature change`) on top of
  *k*.
- **Monorepo (`vendor/a/`)**: *a* cloned *k*. On `main`, the pull *p*
  brought in *m*. On `feature`, *b* (`feature change`) was pushed as *f*,
  and then rebased onto *p* as *c*.

<div align="center">

![The monorepo, a, p on main and c on feature, with H at c; upstream, k with two children, m on main, which is U(H), and f on feature, which is T; R is c prime, dashed, on top of m](feature-branch-behind-default-branch.drawio.svg)

</div>

Four branches take part, two in each repository: `main` and `feature`
in the monorepo, *p* and *c*, and `main` and `feature` upstream, *m*
and *f*. `git-splice` syncs the monorepo's folder with the upstream
branch of the same name. Rebasing `feature` onto `main` is plain Git,
and it's one operation that can be done in either repository. Do it in
one of them only, then carry the result across with `git-splice`, in
this order:

<div align="center">

![Two routes, each with the monorepo main and feature on the left and the upstream main and feature on the right. The monorepo first: 1, on main, git splice pull from the upstream main; 2, on feature, git rebase main; 3, git splice push --force to the upstream feature. The upstream first: 1, rebase or merge the upstream feature onto main, for example with Update branch; 2, on feature, git splice pull into the monorepo feature](../../../../docs/images/rebase-feature-branch.drawio.svg)

</div>

- **The monorepo first**, as here: pull on `main`, `git rebase main` on
  `feature`, then [`push --force`](#what-you-want-replace-the-prs-commits).
- **The upstream first**: rebase or merge `feature` onto `main`
  upstream, e.g. with "Update branch" on GitHub, then `pull` on
  `feature`. The pull brings *m* and the rebased feature change in, or,
  after a `git rebase main` here too, only records the rebased branch as
  the synced commit: the folder already has its files.

Mixing the two is [what you don't want](#what-you-dont-want-the-old-commits-back-on-the-pr):
a rebase in the monorepo, then a pull of the PR that was never rebased,
sends the old commits back to the PR.

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
$ check_drawing "$TESTDIR/feature-branch-behind-default-branch.drawio.svg" \
>   a=HEAD~2 p=main c=HEAD k=refs/splices/a/heads/main~1 \
>   m=refs/splices/a/heads/main f=refs/splices/a/heads/feature
ok   feature-branch-behind-default-branch.drawio.svg: 7 commits, 10 arrows, 5 boxes, 1 lanes
```
-->

<!--
```scrut
$ f="$(git rev-parse splices/a/heads/feature)"
```
-->

```scrut
$ git log --graph --format=%s main feature
* feature change
* splice: pull vendor/a from main at 5cc5467
* splice: clone vendor/a from main at bde4164
* initial commit
```

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s main feature
* bump dep
| * feature change
|/  
* seed
```

Ahead 2 are *m* and *c*, behind 1 is *f*, the copy of *b* that upstream
has:

```scrut
$ git splice status
On branch feature

  ahead 2, behind 1  vendor/a
```

Every commit only upstream has is a copy of one the monorepo's `feature`
has, so `push` suggests `--force`, not a `pull`:

```scrut
$ git splice push vendor/a
!!   vendor/a: upstream's 'feature' has only copies of commits this branch has, e.g. from before a 'git rebase' here -- run 'git splice push --force vendor/a' to replace them: a pull would keep both
!!   Failed: vendor/a
[1]
```

`pull --rebase` would take *f* in as it is and drop *m*: *f* lacks it,
since `main` brought it in, not `feature`. It refuses, and prints the
two routes:

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

### What you don't want: the old commits back on the PR

Out of habit, you run the `pull` a refused push usually asks for. It
merges *f*, the copy of the feature change from before the rebase, into
`feature` as the pull *x*. No change is lost, and `lock.txt` stays:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled a35a3ef
```

```scrut
$ cat vendor/a/lock.txt
bump dep
```

The push then sends both copies of the feature change, the rebased *c'*
and the old *f*, joined by *x'*, the copy of the pull:

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

### What you want: replace the PR's commits

Before anyone else builds on the PR, drop the pull, and push the
rebased branch instead, with `--force`. `--keep` refuses if that would
lose uncommitted changes:

```scrut
$ git reset -q --keep HEAD~1
```

```scrut
$ git splice push --force vendor/a
ok   vendor/a: pushed 8613e5d to feature
```

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s feature
* feature change
* bump dep
* seed
```

That's what "Update branch" with a rebase on GitHub makes: *m*, then
the feature change on top. The old copy *f* and the merge *x'* are on
no branch any more:

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

```scrut
$ git splice status
On branch feature

  up to date  vendor/a
```
