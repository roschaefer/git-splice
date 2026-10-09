# Scenario: swapped-splices

Two folders trade places in one commit: what was `vendor/a` is now
`vendor/b`, and the other way around. Each takes its `.splice` along, so
each splice keeps its upstream, under the other's old path. A push of
either path sends only that splice's history: nothing from the folder
that had the path before.

- **Monorepo**: `vendor/a`, a splice of `$UPSTREAM`, cloned at `seed`,
  with a commit not pushed yet, `a's unpushed work`. `vendor/b`, a folder
  that grew in the monorepo.
- **Upstreams**: `$UPSTREAM` has `seed`. `$UPSTREAM-b` is empty, created
  for `vendor/b`.

A path's history alone can't tell the two splices apart: `git log --
vendor/a` lists a's commits before the swap and b's after it. So the
rebuild only uses the path's history from the splice's **mount** on: the
newest commit whose parent had no `.splice` at the path, or one naming
another upstream URL. For `vendor/a` after the swap, that's the swap
itself. See
[the design notes](../../../docs/design/README.md#splicing-out-push-and-the-rebuild).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_swapped_splices
```

`vendor/b` becomes a splice of the empty upstream, and isn't pushed yet:

```scrut
$ git splice init vendor/b "$UPSTREAM-b"
ok   vendor/b: initialized -- 'git splice push vendor/b' publishes it
```

```scrut
$ git splice log
===  vendor/a (main)
< 8da07b1 a's unpushed work  (Test <test@example.com>)
===  vendor/b (upstream has no 'main' branch)
< 0b18046 splice: init vendor/b  (Test <test@example.com>)
```

The swap: three `git mv`, with a temporary name, in one commit.

```scrut
$ git mv vendor/a tmp && git mv vendor/b vendor/a && git mv tmp vendor/b && git commit -q -m "swap a and b"
```

`vendor/a` is now b's splice, with b's file and b's upstream:

```scrut
$ ls vendor/a && git config --file vendor/a/.splice upstream.origin.url
b.txt
$UPSTREAM-b
```

Seen from the path `vendor/a`, the swap didn't add a `.splice`, it
changed the one that was there. That's why "the commit that added
`.splice`" isn't enough to find where b's history at this path starts:
it would find a's clone, and publish a's commits to b's upstream.

```scrut
$ git diff --name-status HEAD^ HEAD -- vendor/a | tr '\t' ' '
M vendor/a/.splice
D vendor/a/a.txt
A vendor/a/b.txt
D vendor/a/file.txt
```

The swap is the mount of the splice now at `vendor/a`, so only the swap
is pushed, as the first commit of `$UPSTREAM-b`:

```scrut
$ git splice log vendor/a
===  vendor/a (upstream has no 'main' branch)
< 02eb4fc swap a and b  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/a
??   vendor/a: upstream has no 'main' branch yet -- this push creates it
ok   vendor/a: pushed 02eb4fc to main
```

```scrut
$ git -C "$UPSTREAM-b" log --format=%s main && git -C "$UPSTREAM-b" ls-tree --name-only main
swap a and b
b.txt
```

`a's unpushed work` and `a.txt` didn't reach b's upstream.

The other direction: `vendor/b` is a's splice now. Its push goes to
`$UPSTREAM`, so a's commits belong there, but the rebuild doesn't follow
moves yet, and `a's unpushed work` is folded into the swap commit. This
is the known bug [#4](https://github.com/roschaefer/git-splice/issues/4),
with the same workaround: push before moving a splice.

```scrut
$ git splice log vendor/b
===  vendor/b (main)
< df45f51 swap a and b  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/b
ok   vendor/b: pushed df45f51 to main
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
swap a and b
seed
```
