# Scenario: swapped-splices

Two folders trade places in one commit: what was `vendor/a` is now
`vendor/b`, and the other way around. Each takes its `.splice` along, so
each splice keeps its upstream, and its history, under the other's old
path. A push of either path sends only that splice's history: nothing
from the folder that had the path before.

- **Monorepo**: `vendor/a`, a splice of `$UPSTREAM`, cloned at `seed`,
  with a commit not pushed yet, `a's unpushed work`. `vendor/b`, a folder
  that grew in the monorepo.
- **Upstreams**: `$UPSTREAM` has `seed`. `$UPSTREAM-b` is empty, created
  for `vendor/b`.

A path's history alone can't tell the two splices apart: `git log --
vendor/a` lists a's commits before the swap and b's after it. Their ids
can: each splice got its own when it was cloned or initialized, and it
moves with the `.splice`. So the rebuild follows each splice back to the
path where its id was before the swap, and continues there. See
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
changed the one that was there. Only the id shows that it's another
splice now, which came from `vendor/b`. The path's own history before the
swap is a's, and isn't b's to publish.

```scrut
$ git diff --name-status HEAD^ HEAD -- vendor/a | tr '\t' ' '
M vendor/a/.splice
D vendor/a/a.txt
A vendor/a/b.txt
D vendor/a/file.txt
```

b's history continues from `vendor/b`, where it was `init`. The swap
changed none of b's files, so it adds nothing:

```scrut
$ git splice log vendor/a
===  vendor/a (upstream has no 'main' branch)
< 0b18046 splice: init vendor/b  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/a
??   vendor/a: upstream has no 'main' branch yet -- this push creates it
ok   vendor/a: pushed 0b18046 to main
```

```scrut
$ git -C "$UPSTREAM-b" log --format=%s main && git -C "$UPSTREAM-b" ls-tree --name-only main
splice: init vendor/b
b.txt
```

`a's unpushed work` and `a.txt` didn't reach b's upstream.

The other direction: `vendor/b` is a's splice now, and its history
continues from `vendor/a`, with `a's unpushed work` as a commit of its
own:

```scrut
$ git splice log vendor/b
===  vendor/b (main)
< 8da07b1 a's unpushed work  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/b
ok   vendor/b: pushed 8da07b1 to main
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
a's unpushed work
seed
```
