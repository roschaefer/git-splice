# Scenario: diverged-then-pulled

Both sides changed different files, then the remote's change was pulled in.
The local change is still waiting to be pushed.

- **Monorepo (`vendor/a`)**: added at `seed`, then a local commit adding
  `local.txt`, then `git subtree pull --squash` of the upstream change. The
  merge has no conflict.
- **Remote**: `seed`, then a commit adding `upstream.txt`. It has never
  seen `local.txt`.

The pull moved the sync point to the remote's tip, but `vendor/a` still has
`local.txt` on top of it. Local changes must be measured against what the
sync point recorded from the remote, not against the merge commit that
brought it in: the merge commit already contains `local.txt`, which would
hide it from `push`.

## Output

`scenario_diverged_then_pulled` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_diverged_then_pulled
```
-->

`status` and `diff` show only `local.txt`, and `push` sends it:

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (push)
 local.txt | 1 +
 1 file changed, 1 insertion(+)
```

```scrut
$ git subtrees diff
===  vendor/a
diff --git a/local.txt b/local.txt
new file mode 100644
index 0000000..d012455
--- /dev/null
+++ b/local.txt
@@ -0,0 +1 @@
+local change
```

```scrut
$ git subtrees push
git push using:  vendor/a main
To $UPSTREAM
   9887ec6..6e09454  6e094549bc91a3200415d8bd70f68423b6f4ff1b -> main
ok   vendor/a: pushed
```

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (up to date)
```
