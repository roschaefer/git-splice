# Scenario: nested-splices

One splice below another. a's upstream uses git splice itself: it has b's
upstream spliced in at `b/`, with a `b/.splice` of its own. Cloning a's
upstream into the monorepo brings that `.splice` along, so `vendor/a/b`
is a splice in the monorepo too.

- **b's upstream** (`$UPSTREAM-b.git`, reached as
  `https://git.example.com/b.git`): `b seed`.
- **a's upstream** (`$UPSTREAM`): `a seed`, then `add b`, which spliced
  b's upstream in at `b/`.
- **Monorepo**: `vendor/a` from a's upstream, and `vendor/a/b` below it,
  from b's upstream, both fetched.

Each push sends its folder without its own `.splice`. So a's push sends
b's `.splice` with b's files, and in a's upstream, `b/` stays a splice
that git splice can pull and push there.
[The design](../../../docs/design/README.md#refs-instead-of-remotes)
explains why both repositories agree on b's state.

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

A change in b is a change in a too:

```scrut
$ echo "b local" >>vendor/a/b/file.txt && git commit -q -a -m "b local"
```

```scrut
$ git splice status
ok   vendor/a -> main (push: ahead 1)
ok   vendor/a/b -> main (push: ahead 1)
```

Each push sends its own folder, bottom-up: b's upstream gets the change,
without `.splice`:

```scrut
$ git splice push vendor/a/b vendor/a
ok   vendor/a/b: pushed 701ab17 to main
ok   vendor/a: pushed 9555a29 to main
```

```scrut
$ git -C "$UPSTREAM-b.git" ls-tree -r --name-only main
file.txt
```

a's upstream gets it too, with b's `.splice`:

```scrut
$ git -C "$UPSTREAM" ls-tree -r --name-only main
b/.splice
b/file.txt
file.txt
```

## a's upstream pulls b

Someone working in a's upstream pulls b's new commit there, and pushes
the result. (`seed_bare_repo`, from
[`fixtures.bash`](../../helpers/fixtures.bash), commits a line to a file
of b's upstream.)

```scrut
$ seed_bare_repo "$UPSTREAM-b.git" "b upstream change" main other.txt
```

```scrut
$ git clone -q "$UPSTREAM" ../a-work && git -C ../a-work -c user.name=Test -c user.email=test@example.com splice pull b && git -C ../a-work push -q origin main
ok   b fetched
ok   b: pulled 527b1a2
```

Meanwhile, the monorepo has a new commit in b:

```scrut
$ echo "b local 2" >>vendor/a/b/file.txt && git commit -q -a -m "b local 2"
```

Pulling a brings in b's `.splice` as a's upstream has it, with a newer
synced commit. `pull` fetches the splices below a too, so that commit is
there:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved 9555a29..b50a1ff)
ok   vendor/a/b fetched (main moved 701ab17..527b1a2)
ok   vendor/a: pulled b50a1ff
```

The pull is now b's boundary. b's unpushed commit is kept, and the next
push joins it with the change in b's upstream:

```scrut
$ git splice status
ok   vendor/a -> main (push: ahead 2)
ok   vendor/a/b -> main (push: ahead 2)
```

```scrut
$ git splice push vendor/a/b && git -C "$UPSTREAM-b.git" log --graph --format=%s main
ok   vendor/a/b: pushed 3a0104a to main
*   splice: pull vendor/a from main at b50a1ff
|\  
| * b upstream change
* | b local 2
|/  
* b local
* b seed
```

If the monorepo had pulled b as well, to a different commit, the pull of
a would have conflicted: see
[Limits](../../../docs/design/README.md#limits).

Once the monorepo has pushed a change in b, another monorepo that splices
a in can't push from b without a conflict, a known limitation
([#74](https://github.com/roschaefer/git-splice/issues/74)):
[spliced into another monorepo](spliced-elsewhere.md).
