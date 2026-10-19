# Scenario: nested-splices, three levels

Three upstreams nest: the outer one splices the middle one in at `b/`,
as in the [parent scenario](../README.md), and the middle one splices
the inner one in at `c/`. The monorepo has the outer one at `vendor/a/`,
so the inner one is at `vendor/a/b/c/`.

- **Monorepo**: `vendor/a/`, with `vendor/a/b/` and `vendor/a/b/c/` in
  it, as their upstreams have them.
- **Upstreams**: the inner one has `c seed`; the middle one has `b seed`
  and the inner one spliced in; the outer one has `a seed` and the
  middle one spliced in.

As in [spliced elsewhere](../spliced-elsewhere.md), the monorepo pushes
a change in `vendor/a/b/c/`, and another monorepo splices the outer
upstream in. There, the history of `vendor/a/b/c/` up to the clone comes
from an upstream above. But not from the middle one:
`vendor/a/b/.splice` still names the synced commit from before the
change, since a push writes nothing to the monorepo, and the middle
upstream at that commit doesn't have it. The outer upstream does. So the
rebuild takes the inner splice's history from the splice above whose
last pull is the newest, and on a tie, as here, from the outermost one:
its upstream has the ones below too, at least as new as their own synced
commits. Before, it took the middle one's, made the change a new commit,
and `vendor/a/b/c/` read as diverged after its next change.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=4 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1="url.$UPSTREAM-c.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/c.git GIT_CONFIG_KEY_2=user.name GIT_CONFIG_VALUE_2=Other GIT_CONFIG_KEY_3=user.email GIT_CONFIG_VALUE_3=other@example.com
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_three_levels https://git.example.com/b.git https://git.example.com/c.git
```

The monorepo changes `vendor/a/b/c/` and pushes all three, bottom-up:

```scrut
$ echo "c local" >>vendor/a/b/c/file.txt &&
>   git commit -q -a -m "c local" &&
>   git splice push vendor/a/b/c vendor/a/b vendor/a
ok   vendor/a/b/c: pushed 8dd94ad to main
ok   vendor/a/b: pushed 50ab272 to main
ok   vendor/a: pushed daa485c to main
```

`b/.splice`, as the outer upstream has it now, still names the middle
upstream's commit from before the change:

```scrut
$ git -C "$UPSTREAM" show main:b/.splice |
>   git config --file - splice.commit |
>   xargs git -C "$UPSTREAM-b.git" log -1 --format=%s
add c
```

## Another monorepo splices the outer upstream in

```scrut
$ git init -q -b main ../other &&
>   cd ../other &&
>   git commit -q --allow-empty -m "other monorepo"
```

```scrut
$ git splice clone "$UPSTREAM" vendor/a && git splice fetch
===  vendor/a: fetching $UPSTREAM
ok   vendor/a: cloned daa485c from main
ok   vendor/a fetched
ok   vendor/a/b fetched
ok   vendor/a/b/c fetched
```

`vendor/a/b/c/` is up to date, and its first change here is the only one
to push:

```scrut
$ echo "c other" >>vendor/a/b/c/file.txt && git commit -q -a -m "c other"
```

```scrut
$ git splice status vendor/a/b/c
On branch main

  ahead 1  vendor/a/b/c
```

```scrut
$ git splice log vendor/a/b/c
===  vendor/a/b/c (main)
< 014dd58 c other  (Other <other@example.com>)
```
