# Scenario: upstream-moved

The upstream moved, e.g. to another host, and `.splice` gets its new URL
while a commit is still unpushed. The next push sends the right content,
but squashes the unpushed commit into the commit that changed the URL:
its message and author are lost. This is a known limitation,
[#78](https://github.com/roschaefer/git-splice/issues/78).

- **Monorepo (`vendor/a`)**: cloned at `seed`, then a local commit,
  `local change`, not pushed yet.
- **Upstream**: `seed`, at `$UPSTREAM` and, as a copy, at
  `$UPSTREAM-moved`.

A splice's history starts at its **mount**: the newest commit whose
parent had no `.splice` at the path, or one naming another upstream URL.
The URLs are the splice's identity, so a new URL looks like another
splice took over the path, as after
[two splices swapped paths](../../../swapped-splices/README.md). Starting
over keeps another splice's history from reaching this upstream, at the
price of this case. See
[the design notes](../../../../../docs/design/README.md#splicing-out-push-and-the-rebuild).

Workaround: push before changing the URL.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_upstream_moved
```

```scrut
$ git splice log
===  vendor/a (main)
< e859a6b local change  (Test <test@example.com>)
```

```scrut
$ git config --file vendor/a/.splice upstream.origin.url "$UPSTREAM-moved" && git commit -q -am "the upstream moved"
```

```scrut
$ git splice fetch vendor/a
ok   vendor/a fetched
```

`local change` is gone from the list, the URL change takes its place:

```scrut
$ git splice log
===  vendor/a (main)
< 004731d the upstream moved  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 004731d to main
```

```scrut
$ git -C "$UPSTREAM-moved" log --format=%s main
the upstream moved
seed
```

```scrut
$ git -C "$UPSTREAM-moved" show --format= main
diff --git a/file.txt b/file.txt
index e31de1f..d939bfa 100644
--- a/file.txt
+++ b/file.txt
@@ -1 +1,2 @@
 seed
+local change
```
