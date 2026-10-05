# Scenario: squash-merged-pull

A pull on a feature branch, squash-merged into `main`.

- **Upstream**: `seed` on `main`, and someone else's commit on `feature`.
- **Monorepo (`vendor/a`)**: cloned at `seed`. On `feature`, `git splice
  pull` brought in the upstream commit. `feature` was squash-merged into
  `main` and deleted, then a local commit followed on `main`.

A squash merge keeps the content and drops the history. With `git subtree`,
that lost the sync point. Here the squash merge itself
changed `.splice`, so it is the new boundary, and the rebuild starts at the
pulled upstream commit: a push sends only the local commit.

## Output

`scenario_squash_merged_pull` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_squash_merged_pull
```
-->

```scrut
$ git log --format=%s
local change
feature (squash-merged)
add vendor/a
initial commit
```

```scrut
$ git splice status
ok   vendor/a -> main (push: ahead 2)
```

```scrut
$ git splice log
===  vendor/a (main)
< 5c5de89 local change  (Test <test@example.com>)
< 223f9b4 upstream feature work  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 5c5de89 to main
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
local change
upstream feature work
seed
```
