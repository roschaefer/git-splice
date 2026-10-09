# Scenario: nested-splices, three levels

Three upstreams nest: a splices b in at `b/`, as in the
[parent scenario](../README.md), and b splices c in at `c/`. The
monorepo has a at `vendor/a`, so c is at `vendor/a/b/c`.

- **Monorepo**: a, with b and c in it, as their upstreams have them.
- **Upstreams**: c has `c seed`; b has `b seed` and c spliced in; a has
  `a seed` and b spliced in.

As in [spliced elsewhere](../spliced-elsewhere.md), the monorepo pushes a
change in c, and another monorepo splices a in. There, c's history up to
the clone comes from an upstream above. But not from b's: b's `.splice`
still names b's synced commit from before the change, since a push writes
nothing to the monorepo, and b's upstream at that commit doesn't have it.
a's upstream does. So the rebuild takes c's history from the splice above
whose boundary is the newest, and on a tie, as here, from the outermost
one: its upstream has the ones below too, at least as new as their own
synced commits. Before, it took b's, made the change a new commit, and c
read as diverged after its next change.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=4 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1="url.$UPSTREAM-c.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/c.git GIT_CONFIG_KEY_2=user.name GIT_CONFIG_VALUE_2=Other GIT_CONFIG_KEY_3=user.email GIT_CONFIG_VALUE_3=other@example.com
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_three_levels https://git.example.com/b.git https://git.example.com/c.git
```

The monorepo changes c and pushes all three, bottom-up:

```scrut
$ echo "c local" >>vendor/a/b/c/file.txt && git commit -q -a -m "c local" && git splice push vendor/a/b/c vendor/a/b vendor/a
ok   vendor/a/b/c: pushed 8dd94ad to main
ok   vendor/a/b: pushed 6fc6beb to main
ok   vendor/a: pushed 448599c to main
```

b's `.splice`, as a's upstream has it now, still names b's commit from
before the change:

```scrut
$ git -C "$UPSTREAM" show main:b/.splice | git config --file - splice.commit | xargs git -C "$UPSTREAM-b.git" log -1 --format=%s
add c
```

## Another monorepo splices a in

```scrut
$ git init -q -b main ../other && cd ../other && git commit -q --allow-empty -m "other monorepo"
```

```scrut
$ git splice clone "$UPSTREAM" vendor/a && git splice fetch
===  vendor/a: fetching $UPSTREAM
ok   vendor/a: cloned 448599c from main
ok   vendor/a fetched
ok   vendor/a/b fetched
ok   vendor/a/b/c fetched
```

c is up to date, and its first change here is the only one to push:

```scrut
$ echo "c other" >>vendor/a/b/c/file.txt && git commit -q -a -m "c other"
```

```scrut
$ git splice status vendor/a/b/c
ok   vendor/a/b/c -> main (push: ahead 1)
```

```scrut
$ git splice log vendor/a/b/c
===  vendor/a/b/c (main)
< 014dd58 c other  (Other <other@example.com>)
```
