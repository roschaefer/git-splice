# Scenario: paging output on Windows

On Windows, `git splice log` and `diff` currently write directly to the
terminal instead of starting Git's configured pager. Pipe their output to
a pager explicitly. See [known bugs and restrictions](../../99-known-bugs.md#input-and-platform-restrictions).

The commands below use `more`, available in Git Bash as well as on the
POSIX systems used by the documentation checks. They check the explicit
paging workaround; the Windows-specific automatic-pager behaviour is not
exercised by that runner.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds a splice with one local commit to inspect:

```scrut
$ build_scenario scenario_platform_restrictions
```

```scrut
$ git splice log vendor/a | more
===  vendor/a (main)
< e859a6b local change  (Test <test@example.com>)
```

```scrut
$ git splice diff vendor/a | more
===  vendor/a
diff --git a/file.txt b/file.txt
index e31de1f..d939bfa 100644
--- a/file.txt
+++ b/file.txt
@@ -1 +1,2 @@
 seed
+local change
```
