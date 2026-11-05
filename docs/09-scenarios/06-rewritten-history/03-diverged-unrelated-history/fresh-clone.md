# Fresh clone

In the [same state](README.md), upstream rebuilt from scratch, a
colleague clones the monorepo. The clone has no fetched refs, and the
upstream no longer has the synced commit *k*, so no fetch brings it. A
pull says that first, then prints the same ways out as in the monorepo
that fetched *k* before.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_diverged_unrelated_history
```

```scrut
$ git clone -q --no-local . ../fresh && cd ../fresh && git config user.name Test && git config user.email test@example.com
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
!!   vendor/a: its synced commit bde4164 isn't on its upstream any more
??   vendor/a: upstream and the splice share no history -- pick a side:

  # keep the upstream version, discarding local changes under vendor/a:
  git rm -r -q -- vendor/a && git commit -m 'remove vendor/a'
  git splice clone -- $UPSTREAM vendor/a

  # OR: keep both, resolving every file that differs as a conflict:
  git rm -q -- vendor/a/.splice && git commit -m 'unsplice vendor/a'
  git splice clone --merge -- $UPSTREAM vendor/a

  # OR: keep the monorepo version, overwriting upstream's branch:
  git splice push --force -- vendor/a

!!   Failed: vendor/a
[1]
```
