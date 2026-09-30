# Scenario: feature-branch-changed

Like `feature-branch-unchanged`, but the subtree has local changes on the
feature branch.

- **Monorepo (`vendor/a`)**: added at `seed` on `main`, then a new
  `feature` branch with one commit under `vendor/a`.
- **Remote**: only has `main`, at `seed`. No `feature` branch.

## Output

`scenario_feature_branch_changed` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_feature_branch_changed
```
-->

The scenario sets no base branch, so the commands pass `--base main`:

```scrut
$ git subtrees status --base main
ok   vendor/a -> $UPSTREAM (no 'feature' branch on remote; changed since 'main' -- push would create it)
 vendor/a/file.txt | 1 +
 1 file changed, 1 insertion(+)
```

```scrut
$ git subtrees diff --base main
===  vendor/a
diff --git a/file.txt b/file.txt
index e31de1f..d939bfa 100644
--- a/file.txt
+++ b/file.txt
@@ -1 +1,2 @@
 seed
+local change
```

```scrut
$ git subtrees push --base main
??   vendor/a: remote has no 'feature' branch yet -- this push will create it (changed since 'main')
git push using:  vendor/a feature
To $UPSTREAM
 * [new branch]      e859a6b3f55b1e873e69f2dc39247c735e67df6a -> feature
ok   vendor/a: pushed
```

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (up to date)
```
