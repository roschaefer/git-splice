# Scenario: nested-splices, a pull retried after the synced commit below is gone

> **Known bug, [#274](https://github.com/roschaefer/git-splice/issues/274).** This page shows what `git-splice` does today, bug included. See [all known bugs](../../08-known-bugs.md).

As in [dropped below](dropped-below.md), a pull of `vendor/a/` moves
`vendor/a/b/` to a synced commit the inner upstream dropped from its
`main`. Here, the inner upstream has also deleted it, so no fetch can
get it any more. The pull fails, but a second try of the same command
succeeds without a word about `vendor/a/b/`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1=Test GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=test@example.com
```
-->

[`setup.bash`](setup.bash) builds the state of the [README](README.md):
the outer upstream with the inner one spliced in at `b/`, cloned into
the monorepo:

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

## The inner upstream deletes a change the outer upstream has

A change in the inner upstream, *c* (`b change`), on top of *m*
(`b seed`):

```scrut
$ seed_bare_repo "$UPSTREAM-b.git" "b change" main other.txt >/dev/null 2>&1
```

In a clone of the outer upstream, `b/` pulls it, and the outer upstream
gets it as *n*, on top of *k* (`a seed`) and *l* (`add b`):

```scrut
$ git clone -q "$UPSTREAM" ../a-work &&
>   cd ../a-work &&
>   git splice pull b &&
>   git push -q origin HEAD:main &&
>   cd ../monorepo
ok   b fetched
ok   b: pulled 95165ad
```

The inner upstream drops *c* again:

```scrut
$ git -C "$UPSTREAM-b.git" update-ref refs/heads/main refs/heads/main^
```

and deletes it for good, as a server's garbage collection would:

```scrut
$ git -C "$UPSTREAM-b.git" reflog expire --expire=now --all &&
>   git -C "$UPSTREAM-b.git" gc -q --prune=now
```

## The first pull fails

The pull of `vendor/a/` moves `vendor/a/b/` to *c*, which the inner
upstream doesn't have any more:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved *..*) (glob)
ok   vendor/a/b fetched
ok   vendor/a: pulled * (glob)
ok   vendor/a/b fetched
!!   vendor/a/b: its synced commit 95165ad, from a pull above, isn't on its upstream any more
!!   Failed: vendor/a/b
[1]
```

The pull of `vendor/a/` is committed all the same:

```scrut
$ git log -1 --format=%s
splice: pull vendor/a from main at * (glob)
```

## The retry succeeds

The same command again. Only a `.splice` that changed in this run gets
checked, and the one of `vendor/a/b/` changed in the first:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a/b fetched
ok   vendor/a: nothing to pull
```

Nothing is fixed. `status` still finds the synced commit missing:

```scrut
$ git splice status
On branch main

  ?? synced commit 95165ad isn't here  vendor/a/b  run 'git splice fetch vendor/a/b', or check that upstream has it

  up to date                           vendor/a
```
