# Scenario: feature-branch-behind-default-branch

A feature branch was pushed, so upstream has it as a PR. Then upstream's
`main` moved on, and the monorepo's `main` pulled that in. The PR is now
behind `main`: GitHub says "This branch is out-of-date with the base
branch". To bring it up to date, `feature` is rebased onto `main`.

- **Upstream**: *k* (`seed`) on `main`, then *m* (`bump dep`), which adds
  `lock.txt`. `feature`, the PR, is *f* (`feature change`) on top of
  *k*.
- **Monorepo (`vendor/a/`)**: *a* cloned *k*. On `main`, the pull *p*
  brought in *m*. On `feature`, *b* (`feature change`) was pushed as *f*.

<div align="center">

![The monorepo, a with two children, p on main and b on feature, which is H; upstream, k, which is U(H), with two children, m on main and f, which is T, R and feature](feature-branch-behind-default-branch.drawio.svg)

</div>

Four branches take part, two in each repository: `main` and `feature`
in the monorepo, *p* and *b*, and `main` and `feature` upstream, *m*
and *f*. `git-splice` syncs the monorepo's folder with the upstream
branch of the same name. Rebasing `feature` onto `main` is plain Git,
and it's one operation that can be done in either repository. Do it in
one of them only, then carry the result across with `git-splice`, in
this order:

<div align="center">

![Two strategies, each with the monorepo main and feature on the left and the upstream main and feature on the right. The monorepo first: 1, on main, git splice pull from the upstream main; 2, on feature, git rebase main; 3, git splice push --force to the upstream feature. The upstream first: 1, rebase or merge the upstream feature onto main, for example with Update branch; 2, on feature, git splice pull into the monorepo feature](../../../../docs/images/rebase-feature-branch.drawio.svg)

</div>

- **[What you don't want](dont-pull-the-old-commits.md)**: a rebase in
  the monorepo, then a pull of the PR that was never rebased. The next
  push sends the old commits back to the PR.
- **[Strategy 1, the monorepo first](monorepo-first.md)**: `git rebase
  main` on `feature`, then `git splice push --force`.
- **[Strategy 2, the upstream first](upstream-first.md)**: rebase
  `feature` onto `main` upstream, e.g. with "Update branch" on GitHub,
  then `git splice pull` on `feature`.

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
>   a=HEAD~1 b=HEAD p=main k=refs/splices/a/heads/main~1 \
>   m=refs/splices/a/heads/main f=refs/splices/a/heads/feature
ok   feature-branch-behind-default-branch.drawio.svg: 6 commits, 9 arrows, 5 boxes, 1 lanes
```
-->

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s main feature
* bump dep
| * feature change
|/  
* seed
```

`git-splice` compares `feature` with upstream's `feature` only, and
those match. That the PR is behind `main` is a matter between the two
branches of each repository:

```scrut
$ git splice status
On branch feature

  up to date  vendor/a
```
