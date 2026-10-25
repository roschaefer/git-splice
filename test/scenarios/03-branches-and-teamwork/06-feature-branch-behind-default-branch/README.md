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

Four branches take part, two in each repository. `git-splice` syncs the
folder with the upstream branch of the same name, across. Rebasing
`feature` onto `main` is plain Git, up and down, and it's one operation
that can be done on either side:

```text
                git splice pull/push
  monorepo main  <------------------>  upstream main
       ^                                    ^
       | git rebase main                    | "Update branch" on GitHub,
       |                                    | or a rebase in a clone
       |                                    |
  monorepo feature <---------------->  upstream feature (the PR)
                git splice pull/push
```

Do it on one side only, then carry the result across with `git-splice`:

- **The monorepo first**, as here: `git rebase main`, then
  [`push --force`](push-force.md).
- **The upstream first**: [rebase](rebased-upstream.md) or
  [merge](merged-upstream.md) `feature` upstream, then `pull`.

Mixing the two, a rebase in the monorepo and a pull of the PR that was
never rebased, joins two bases for the same branch: `feature` upstream
still lacks *m*, which the monorepo's `feature` has now. A
[`pull`](pull.md) keeps both copies of the feature change, and
[`pull --rebase`](pull-rebase.md) refuses, since it would drop *m*.

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
