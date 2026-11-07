# Scenario: nested-splices, three levels: an upstream renamed in between

`pull --upstream origin` pulls each selected splice from its upstream
named `origin`. A splice without one stops the command, before anything
is pulled.

A pull of the outer splice can change the `.splice` of the inner one:
here it names the inner upstream `fork` for a while, until the middle
splice's pull names it `origin` again. A nested splice is pulled one
level down, and reads its `.splice` there, when its own pull starts
([pulled through the levels](../pulled-through-the-levels.md)). That's
after the pulls above it, so the inner splice finds `origin` again, and
all three are pulled.

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

The pull of `vendor/a/` leaves `vendor/a/b/c/` without an `origin`. The
pull of `vendor/a/b/` names it again, and the pull of `vendor/a/b/c/`
finds it:

```scrut
$ git splice pull --all --upstream origin
ok   vendor/a fetched (main moved 5bbd8de..217112c)
ok   vendor/a: pulled 217112c
ok   vendor/a/b fetched (main moved 8333d5f..ecb9e0e)
ok   vendor/a/b/c fetched
ok   vendor/a/b: pulled ecb9e0e
ok   vendor/a/b/c fetched
ok   vendor/a/b/c: nothing to pull
```

```scrut
$ git log --format=%s -2
splice: pull vendor/a/b from main at ecb9e0e
splice: pull vendor/a from main at 217112c
```

```scrut
$ git config --file vendor/a/b/c/.splice --name-only --get-regexp '^upstream\.'
upstream.origin.url
```
