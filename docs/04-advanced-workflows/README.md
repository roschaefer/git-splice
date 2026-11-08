# Rebasing a feature branch

A feature branch was pushed, so upstream has it as a PR. Then upstream's
`main` moved on, and the monorepo's `main` pulled that in. The PR is now
behind `main`: GitHub says "This branch is out-of-date with the base
branch". To bring it up to date, `feature` is rebased onto `main`.
*m* adds `lock.txt`:

<div align="center">

![The monorepo, a with two children, p on main and b on feature, which is H; upstream, k, which is U(H), with two children, m on main and b prime, which is T, R and feature](feature-branch-behind-default-branch.drawio.svg)

</div>

## The rebase strategies

`git-splice` syncs with the upstream branch of the same name. Rebasing
`feature` onto `main` is a separate Git operation: do it in one repository
only, then carry the result across with `git-splice`:

<div align="center">

![The two rebase strategies, each with the monorepo main and feature on the left and the upstream main and feature on the right. Rebase via upstream: 1, rebase or merge the upstream feature onto main, for example with Update branch; 2, on feature, git splice pull into the monorepo feature. Rebase via monorepo: 1, on main, git splice pull from the upstream main; 2, on feature, git rebase main; 3, git splice push --force to the upstream feature](../images/rebase-strategies.drawio.svg)

</div>

| Strategy | How to use it | When to use it |
| --- | --- | --- |
| [Via upstream](01-rebase-strategies/README.md) | Click "Update branch" on GitHub, or rebase in a clone of the upstream, then `git splice pull` on `feature`. | The simple default. |
| [Via monorepo](01-rebase-strategies/01-rebase-via-monorepo.md) | On `feature`, run `git rebase main`, then `git splice push --force`. | When GitHub can't rebase, resolve conflicts with the whole monorepo to build and test. Rewrites the monorepo's feature branch and overwrites the PR; use only when nobody else pushes to them. |

**[Don't mix the strategies](01-rebase-strategies/02-dont-pull-the-old-commits.md)**: a rebase
in the monorepo, then a pull of the PR that was never rebased, sends the
old commits back to the PR.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../09-scenarios/readme-setup.sh" && source "$TESTDIR/rebase-setup.bash"
```
-->

[`rebase-setup.bash`](rebase-setup.bash) builds this state:

```scrut
$ build_scenario scenario_feature_branch_behind_default_branch
```

<!--
```scrut
$ check_drawing "$TESTDIR/feature-branch-behind-default-branch.drawio.svg" \
>   p=main m=refs/splices/a/heads/main
ok   feature-branch-behind-default-branch.drawio.svg: 6 commits, 9 arrows, 5 boxes, 1 lanes
```
-->

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s main feature
* m: bump dep
| * b: feature change
|/  
* k: seed
```

`git-splice` compares `feature` with upstream's `feature` only, and
those match. That the PR is behind `main` is a matter between the two
branches of each repository:

```scrut
$ git splice status
On branch feature

  up to date  vendor/a
```
