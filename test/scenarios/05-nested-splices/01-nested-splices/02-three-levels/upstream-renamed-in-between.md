# Scenario: nested-splices, three levels: an upstream renamed in between

`pull --upstream origin` pulls each selected splice from its upstream
named `origin`. A splice without one stops the command, before anything
is pulled.

A pull of the outer splice can change the `.splice` of the inner one,
and `pull` reads it again right after that merge. If the inner upstream
is named `fork` at that point, the command stops there, though the
middle splice's pull, still to come, would name it `origin` again.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=4 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1="url.$UPSTREAM-c.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/c.git GIT_CONFIG_KEY_2=user.name GIT_CONFIG_VALUE_2=Test GIT_CONFIG_KEY_3=user.email GIT_CONFIG_VALUE_3=test@example.com
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_three_levels https://git.example.com/b.git https://git.example.com/c.git
```

## The middle upstream renames the inner upstream, and back

The middle upstream calls its inner upstream `fork` for one commit:

```scrut
$ git clone -q https://git.example.com/b.git ../b-work &&
>   git -C ../b-work config --file c/.splice --rename-section upstream.origin upstream.fork &&
>   git -C ../b-work commit -q -am "c: origin is fork" &&
>   git -C ../b-work push -q origin main
```

The outer upstream pulls the middle one at that commit:

```scrut
$ git clone -q "$UPSTREAM" ../a-work &&
>   cd ../a-work &&
>   git splice pull b
ok   b fetched
ok   b/c fetched
ok   b: pulled 4fd19b5
```

```scrut
$ git push -q origin main && cd ../monorepo
```

Then the middle upstream names it `origin` again:

```scrut
$ git -C ../b-work config --file c/.splice --rename-section upstream.fork upstream.origin &&
>   git -C ../b-work commit -q -am "c: fork is origin" &&
>   git -C ../b-work push -q origin main
```

So, as `pull --all` goes top-down, `vendor/a/b/c/` has an `origin` before
the pull of `vendor/a/`, none after it, and one again after the pull of
`vendor/a/b/`.

## `pull --all --upstream origin`

Right after the pull of `vendor/a/`, `pull` reads `vendor/a/b/c/.splice`
again, finds no `origin`, and stops. `vendor/a/b/` isn't pulled:

```scrut
$ git splice pull --all --upstream origin
ok   vendor/a fetched (main moved 5bbd8de..217112c)
ok   vendor/a/b fetched (main moved 8333d5f..ecb9e0e)
ok   vendor/a/b/c fetched
ok   vendor/a: pulled 217112c
!!   vendor/a/b/c has no upstream 'origin' -- its upstream is 'fork'
[1]
```

```scrut
$ git log -1 --format=%s
splice: pull vendor/a from main at 217112c
```

A second run stops before it starts, since `vendor/a/b/c/` has no
`origin` now. Pulling `vendor/a/b/` first gets it back:

```scrut
$ git splice pull --all --upstream origin
!!   no upstream 'origin' in vendor/a/b/c -- name only the splices that have one: vendor/a vendor/a/b
[1]
```

```scrut
$ git splice pull vendor/a/b
ok   vendor/a/b fetched
ok   vendor/a/b/c fetched
ok   vendor/a/b: pulled ecb9e0e
```

```scrut
$ git splice pull --all --upstream origin
ok   vendor/a fetched
ok   vendor/a/b fetched
ok   vendor/a/b/c fetched
ok   vendor/a: nothing to pull
ok   vendor/a/b: nothing to pull
ok   vendor/a/b/c: nothing to pull
```
