# Scenario: feature-branch-changed

The monorepo is on a branch upstream doesn't have, and the splice changed
on it.

- **Monorepo (`vendor/a/`)**: cloned at `seed` on `main`, then the branch
  `feature` with a local commit.
- **Upstream**: only `main`.

"New" counts the commits that no upstream branch has yet.

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
On branch feature

  new, ahead 1  vendor/a  push creates the branch
```

```scrut
$ git splice log
===  vendor/a (upstream has no 'feature' branch)
< e859a6b local change  (Test <test@example.com>)
```

`push` creates `feature` upstream, on top of `main`:

```scrut
$ git splice push vendor/a
??   vendor/a: upstream has no 'feature' branch yet -- this push creates it
ok   vendor/a: pushed e859a6b to feature
```

```scrut
$ git splice status
On branch feature

  up to date  vendor/a
```
