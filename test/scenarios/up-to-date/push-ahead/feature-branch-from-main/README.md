# Scenario: feature-branch-from-main

The monorepo's `main` has a commit that upstream's `main` lacks, and the
monorepo is on a branch cut from it. Upstream protects its `main`, say, so
changes only go in through a PR from another branch.

- **Monorepo (`vendor/a/`)**: cloned at `seed` on `main`, then a local
  commit, then the branch `feature` without further changes.
- **Upstream**: only `main`, at `seed`.

The splice didn't change on `feature`, but `feature` has a commit that
upstream has on no branch. That's what counts: `push` creates `feature`
upstream with it, ready for a PR (#150).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_feature_branch_from_main
```

```scrut
$ git splice status
On branch feature (base: main)

  unchanged, no upstream branch  vendor/a
```

```scrut
$ git splice log
===  vendor/a (upstream has no 'feature' branch)
< e859a6b local change  (Test <test@example.com>)
```

```scrut
$ git splice diff --stat
```

```scrut
$ git splice push vendor/a
ok   vendor/a: nothing to push (upstream has no 'feature' branch; unchanged since 'main')
```

```scrut
$ git splice status
On branch feature (base: main)

  unchanged, no upstream branch  vendor/a
```
