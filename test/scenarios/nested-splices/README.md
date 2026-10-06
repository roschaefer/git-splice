# Scenario: nested-splices

One splice inside another. The outer upstream uses git splice itself: it
has the inner upstream spliced in at `b/`, with a `b/.splice` of its own.
Cloning the outer upstream into the monorepo brings that `.splice` along,
so `vendor/a/b` is a splice in the monorepo too.

- **Inner upstream** (`$UPSTREAM-b.git`, reached as
  `https://git.example.com/b.git`): `b seed`.
- **Outer upstream** (`$UPSTREAM`): `a seed`, then `add b`, which spliced
  the inner upstream in at `b/`.
- **Monorepo**: `vendor/a` from the outer upstream, and `vendor/a/b` from
  the inner one, both fetched.

Each push sends its folder without its own `.splice`. So the outer push
sends the inner `.splice` with the inner splice's files, and in the outer
upstream, `b/` stays a splice that git splice can pull and push there.
[The design](../../../docs/design/README.md#refs-instead-of-remotes)
explains why both repositories agree on the inner splice's state.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

Both splices are up to date:

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
ok   vendor/a/b -> main (up to date)
```

A change in the inner splice is a change in the outer one too:

```scrut
$ echo "b local" >>vendor/a/b/file.txt && git commit -q -a -m "b local"
```

```scrut
$ git splice status
ok   vendor/a -> main (push: ahead 1)
ok   vendor/a/b -> main (push: ahead 1)
```

Each push sends its own folder. The inner upstream gets the change, without
`.splice`:

```scrut
$ git splice push vendor/a/b vendor/a
ok   vendor/a/b: pushed 701ab17 to main
ok   vendor/a: pushed a5c42a7 to main
```

```scrut
$ git -C "$UPSTREAM-b.git" ls-tree -r --name-only main
file.txt
```

The outer upstream gets it too, with the inner `.splice`:

```scrut
$ git -C "$UPSTREAM" ls-tree -r --name-only main
b/.splice
b/file.txt
file.txt
```

## The outer upstream pulls the inner one

Someone working in the outer upstream pulls the inner upstream's new
commit there, and pushes the result. (`seed_bare_repo`, from
[`fixtures.bash`](../../helpers/fixtures.bash), commits a line to a file
of the inner upstream.)

```scrut
$ seed_bare_repo "$UPSTREAM-b.git" "b upstream change" main other.txt
```

```scrut
$ git clone -q "$UPSTREAM" ../outer && git -C ../outer -c user.name=Test -c user.email=test@example.com splice pull b && git -C ../outer push -q origin main
ok   b fetched
ok   b: pulled 527b1a2
```

Meanwhile, the monorepo has a new commit in the inner splice:

```scrut
$ echo "b local 2" >>vendor/a/b/file.txt && git commit -q -a -m "b local 2"
```

Pulling the outer splice brings in the inner `.splice` as the outer
upstream has it, with a newer synced commit. `pull` fetches the inner
splice too, so that commit is there:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved a5c42a7..7eb1486)
ok   vendor/a/b fetched (main moved 701ab17..527b1a2)
ok   vendor/a: pulled 7eb1486
```

The pull is now the inner splice's boundary. Its unpushed commit is kept,
and the next push joins it with the inner upstream's change:

```scrut
$ git splice status
ok   vendor/a -> main (push: ahead 2)
ok   vendor/a/b -> main (push: ahead 2)
```

```scrut
$ git splice push vendor/a/b && git -C "$UPSTREAM-b.git" log --graph --format=%s main
ok   vendor/a/b: pushed cb61f73 to main
*   splice: pull vendor/a from main at 7eb1486
|\  
| * b upstream change
* | b local 2
|/  
* b local
* b seed
```

If the monorepo had pulled the inner splice as well, to a different commit,
the pull of the outer one would have conflicted: see
[Limits](../../../docs/design/README.md#limits).
