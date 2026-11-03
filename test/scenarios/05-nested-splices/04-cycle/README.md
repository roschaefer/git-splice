# Scenario: cycle

The upstream of `vendor/a/` splices in the monorepo, so the monorepo
contains a copy of itself, which contains a copy of itself, and so on: a
[cycle](../../../concepts/nesting/README.md#diamonds-and-cycles).

```text
      M ──> A
      ^     │
      └─────┘   A's upstream splices M in at i/
```

**Not prevented yet.** Nothing refuses a cycle
([#86](https://github.com/roschaefer/git-splice/issues/86)). The plan:
`clone`, `merge` and `pull` refuse to commit a `.splice` with the id of
one above it. That comes one level late, since the monorepo has no
`.splice` of its own: here, `vendor/a/i/` is a copy of the monorepo, but
nothing above it has its id. An upstream URL that is one of the
monorepo's own remotes would show it one level earlier.

- **Monorepo** (published as `https://git.example.com/m.git`):
  `vendor/a/`, a splice of the upstream below.
- **Upstream of `vendor/a/`** (`https://git.example.com/a.git`): `seed`,
  then `add i`, which spliced the monorepo in at `i/`, with `vendor/a/`
  in it.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_cycle
```

### Every pull nests one more copy

The first pull brings in the upstream's `i/`, a copy of the monorepo
with `vendor/a/` in it:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved bde4164..885fc31)
ok   vendor/a: pulled 885fc31
```

```scrut
$ git grep 'id = ' -- '*/.splice' | tr '\t' ' '
vendor/a/.splice: id = 224f2c2563d3b6f7
vendor/a/i/.splice: id = 0ceff458bb3bb1f7
vendor/a/i/vendor/a/.splice: id = 224f2c2563d3b6f7
```

`vendor/a/i/vendor/a/` has the id of `vendor/a/`, above it: the cycle.

Each pull terminates: it reads which splices there are once, before it
merges anything, so a `.splice` that a merge brings in is pulled only by
the next run. But each run finds a deeper one:

```scrut
$ git splice pull --all
ok   vendor/a fetched
ok   vendor/a/i fetched
ok   vendor/a/i/vendor/a fetched
ok   vendor/a: nothing to pull
ok   vendor/a/i: nothing to pull
ok   vendor/a/i/vendor/a: pulled 885fc31
```

```scrut
$ git grep 'id = ' -- '*/.splice' | tr '\t' ' '
vendor/a/.splice: id = 224f2c2563d3b6f7
vendor/a/i/.splice: id = 0ceff458bb3bb1f7
vendor/a/i/vendor/a/.splice: id = 224f2c2563d3b6f7
vendor/a/i/vendor/a/i/.splice: id = 0ceff458bb3bb1f7
vendor/a/i/vendor/a/i/vendor/a/.splice: id = 224f2c2563d3b6f7
```

Once the monorepo is pushed, the `i/` splices sync with a version that
has every level so far, so a pull nests them all once more. The copies
of the nested `.splice` files then conflict, as both sides pulled them
to different commits (the first of the
[design's limits](../../../../docs/design/README.md#limits)).

### The monorepo pushes to itself

`vendor/a/i/` is a splice of the monorepo's own upstream. So its push
sends a copy of the monorepo, from when the upstream of `vendor/a/` last
pulled it, to the monorepo's `main`. A change in the copy:

```scrut
$ echo "note" >vendor/a/i/note.txt &&
>   git add vendor/a/i/note.txt &&
>   git commit -q -m "note in i"
```

```scrut
$ git splice push vendor/a/i
ok   vendor/a/i: pushed 298b249 to main
```

Nobody pushed the monorepo since the setup, so this was a fast-forward.
The monorepo's upstream now has the copy as `main`, which is neither the
monorepo's history nor its tree:

```scrut
$ git -C "$UPSTREAM-m" log --format=%s main
note in i
splice: pull vendor/a/i/vendor/a from main at 885fc31
add vendor/a
initial commit
```

```scrut
$ git -C "$UPSTREAM-m" ls-tree --name-only main
note.txt
vendor
```

```scrut
$ git ls-tree --name-only HEAD
vendor
```

And the monorepo's own push is rejected:

```scrut
$ git push -q https://git.example.com/m.git main
To $UPSTREAM-m
 ! [rejected]        main -> main (non-fast-forward)
error: failed to push some refs to '$UPSTREAM-m'
hint: Updates were rejected because the tip of your current branch is behind
hint: its remote counterpart. If you want to integrate the remote changes,
hint: use 'git pull' before pushing again.
hint: See the 'Note about fast-forwards' in 'git push --help' for details.
[1]
```
