# Scenario: splice-identity/recursion

A splice whose upstream splices in the monorepo. Since a nested
`.splice` travels with its folder, the monorepo's own `vendor/a/.splice`
comes back below `vendor/a`, with the same id.

- **Monorepo** (published as `https://git.example.com/m.git`):
  `vendor/a`, a splice of a's upstream.
- **a's upstream** (`https://git.example.com/a.git`): `seed`, then
  `add i`, which spliced the monorepo in at `i/`, with `vendor/a` in it.

Each pull terminates: it reads which splices there are once, before it
merges anything, so a `.splice` that a merge brings in is pulled only by
the next run. But each run finds a deeper one.

A splice with the same id as one above it shows the cycle: the splice
is inside itself. Two folders side by side with one id are fine
([splice-identity](../README.md)). The check comes one level late,
though, since the monorepo has no `.splice` of its own: `vendor/a/i` is
a copy of the monorepo and has no id in common with anything above it.
Nothing refuses either yet
([#86](https://github.com/roschaefer/git-splice/issues/86)).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_recursion
```

The first pull brings in a's `i/`, a copy of the monorepo with
`vendor/a` in it:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved bde4164..2073178)
ok   vendor/a: pulled 2073178
```

```scrut
$ git grep 'id = ' -- '*/.splice' | tr '\t' ' '
vendor/a/.splice: id = b23b165ba51e3878
vendor/a/i/.splice: id = f0e176bed8253789
vendor/a/i/vendor/a/.splice: id = b23b165ba51e3878
```

`vendor/a/i/vendor/a` has the id of `vendor/a`, above it.

The next pull finds the new splices and pulls `vendor/a/i/vendor/a`,
which brings in another `i/`:

```scrut
$ git splice pull --all
ok   vendor/a fetched
ok   vendor/a/i fetched
ok   vendor/a/i/vendor/a fetched
ok   vendor/a: nothing to pull
ok   vendor/a/i: nothing to pull
ok   vendor/a/i/vendor/a: pulled 2073178
```

```scrut
$ git grep 'id = ' -- '*/.splice' | tr '\t' ' '
vendor/a/.splice: id = b23b165ba51e3878
vendor/a/i/.splice: id = f0e176bed8253789
vendor/a/i/vendor/a/.splice: id = b23b165ba51e3878
vendor/a/i/vendor/a/i/.splice: id = f0e176bed8253789
vendor/a/i/vendor/a/i/vendor/a/.splice: id = b23b165ba51e3878
```

Once the monorepo is pushed, `vendor/a/i` and the `i/` below it sync
with that push, which has every level so far. The next pull would nest
them all again, but the copies of the nested `.splice` files conflict
first, as both sides pulled them to different commits (the first of
the [design's limits](../../../../docs/design/README.md#limits)):

```scrut
$ git push -q https://git.example.com/m.git main && git splice pull --all
ok   vendor/a fetched
ok   vendor/a/i fetched (main moved 30c305a..936a6be)
ok   vendor/a/i/vendor/a fetched
ok   vendor/a/i/vendor/a/i fetched (main moved 30c305a..936a6be)
ok   vendor/a/i/vendor/a/i/vendor/a fetched
ok   vendor/a: nothing to pull
Auto-merging vendor/a/i/vendor/a/i/vendor/a/.splice
CONFLICT (add/add): Merge conflict in vendor/a/i/vendor/a/i/vendor/a/.splice
!!   vendor/a/i: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)
!!   vendor/a/i: pull failed
!!   Not pulled yet: vendor/a/i/vendor/a vendor/a/i/vendor/a/i vendor/a/i/vendor/a/i/vendor/a -- resolve the conflict, run 'git commit', then re-run pull
!!   Failed: vendor/a/i
[1]
```

`vendor/a/i` also pushes to the monorepo's own upstream, which can
replace the monorepo's history with an older copy of itself:
[push-to-itself](push-to-itself.md).
