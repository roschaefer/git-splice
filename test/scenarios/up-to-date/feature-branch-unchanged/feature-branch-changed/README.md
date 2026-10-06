# Scenario: feature-branch-changed

The monorepo is on a branch upstream doesn't have, and the splice changed
on it.

- **Monorepo (`vendor/a`)**: cloned at `seed` on `main`, then the branch
  `feature` with a local commit.
- **Upstream**: only `main`.

"Changed" is measured against the monorepo's base branch: here `main`, the
monorepo's default branch.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_feature_branch_changed
```

```scrut
$ git splice status
ok   vendor/a -> feature (upstream has no such branch; ahead 1 since 'main' -- push would create it)
```

```scrut
$ git splice log
===  vendor/a (upstream has no 'feature' branch)
< e859a6b local change  (Test <test@example.com>)
```

`push` creates `feature` upstream, on top of `main`:

```scrut
$ git splice push vendor/a
??   vendor/a: upstream has no 'feature' branch yet -- this push creates it (changed since 'main')
ok   vendor/a: pushed e859a6b to feature
```

```scrut
$ git splice status
ok   vendor/a -> feature (up to date)
```
