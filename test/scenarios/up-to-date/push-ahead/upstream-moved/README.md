# Scenario: upstream-moved

The upstream moved, e.g. to another host, and `.splice` gets its new URL
while a commit is still unpushed. The next push sends that commit to the
new URL, with its own message and author: the splice's history doesn't
depend on its URL.

- **Monorepo (`vendor/a`)**: cloned at `seed`, then a local commit,
  `local change`, not pushed yet.
- **Upstream**: `seed`, at `$UPSTREAM` and, as a copy, at
  `$UPSTREAM-moved`.

A splice's history starts at its **mount**: the newest commit whose
parent had no `.splice` at the path, or one with another `id`. The id
names the splice, not its upstream, so a new URL keeps it, and the
commits before the change still belong to the splice. Compare
[two splices that swap paths](../../../swapped-splices/README.md), where
the id changes, and so does the history. See
[the design notes](../../../../../docs/design/README.md#splicing-out-push-and-the-rebuild).

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

The id stays when the URL changes:

```scrut
$ git config --file vendor/a/.splice splice.id && git config --file vendor/a/.splice upstream.origin.url "$UPSTREAM-moved" && git commit -q -am "the upstream moved"
b23b165ba51e3878
```

```scrut
$ git config --file vendor/a/.splice splice.id
b23b165ba51e3878
```

```scrut
$ git splice fetch vendor/a
ok   vendor/a fetched
```

`local change` is still the one commit to push. The URL change itself
changes nothing upstream:

```scrut
$ git splice log
===  vendor/a (main)
< e859a6b local change  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed e859a6b to main
```

```scrut
$ git -C "$UPSTREAM-moved" log --format=%s main
local change
seed
```
