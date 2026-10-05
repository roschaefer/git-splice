# Keep the upstream's version

The safe way out of the [same state](README.md) after a local change:
splice the rewritten upstream in again, and redo the local change on top
of it. The upstream's history stays as rewritten, which matters if the
rewrite removed something, like a secret.

## Output

`scenario_upstream_rewritten_equal_tree` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_upstream_rewritten_equal_tree
```
-->

```scrut
$ echo "local change" >>vendor/a/file.txt && git commit -q -a -m "local change" && git splice status
??   vendor/a -> main (unrelated history -- see 'git splice merge vendor/a' for options)
```

Save the local change as a patch, with paths inside the folder:

```scrut
$ git diff --relative=vendor/a HEAD~1 -- vendor/a >../local-change.patch
```

Remove the folder, and splice the rewritten upstream in again:

```scrut
$ git rm -r -q -- vendor/a && git commit -q -m "remove vendor/a" && git splice clone -- "$UPSTREAM" vendor/a
===  vendor/a: fetching $UPSTREAM
ok   vendor/a: cloned bc05937 from main
```

Redo the local change, and push it:

```scrut
$ git apply --directory=vendor/a ../local-change.patch && git commit -q -a -m "local change" && git splice push vendor/a
ok   vendor/a: pushed 5c7d4e1 to main
```

The upstream's history is still the rewritten one:

```scrut
$ git -C "$UPSTREAM" log --format=%s main
local change
release, history rewritten
```
