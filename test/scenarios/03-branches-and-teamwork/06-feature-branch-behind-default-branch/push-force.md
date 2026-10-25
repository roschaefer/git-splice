# Push the rebase

In the [same state](README.md), the monorepo did the rebase, so it's
the side to keep: `push --force` replaces *f* upstream with *m* and the
rebased change. That's what "Update branch" with a rebase on GitHub
would have made. It overwrites whatever upstream's `feature` has, so
it's for a PR nobody else pushes to.

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
$ git splice push --force vendor/a
ok   vendor/a: pushed 8613e5d to feature
```

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s feature
* feature change
* bump dep
* seed
```

```scrut
$ git splice status
On branch feature

  up to date  vendor/a
```
