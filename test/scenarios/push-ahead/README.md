# Scenario: push-ahead

Local made a commit under the subtree path since it was added; the remote
hasn't moved.

- **Monorepo (`vendor/a`)**: added at `seed`, then one more local
  commit under `vendor/a`.
- **Remote**: still at `seed`, unchanged.
- **Common ancestor**: yes -- the add point (`seed`).

## Output

`scenario_push_ahead` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_push_ahead
```
-->

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (push)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

```scrut
$ git subtrees diff
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
$ git subtrees push
git push using:  vendor/a main
To $UPSTREAM
   bde4164..e859a6b  e859a6b3f55b1e873e69f2dc39247c735e67df6a -> main
ok   vendor/a: pushed
```

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (up to date)
```
