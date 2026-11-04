# Scenario: nested-splices, three levels: a fetch fails after a merge above

`pull` goes top-down, and after each merge it reads the `.splice` files
below the merged splice again: the merge may have changed them. A pull
fetches the upstream a changed file names. If that fetch fails, the
splice isn't pulled, and neither is any splice between it and the merge,
in either direction: a failed fetch stops the splices above and below
it, as it does for the fetches before the first merge.

Stopping the ones above matters here. Only their merges can change the
failed splice's `.splice` again, so with them skipped, the failure stays
true until the command ends. Before, the middle splice's pull changed
the inner `.splice` again, the next read found the URL it had read a
moment ago and fetched nothing, and that read's success cleared the
failure. The inner splice was then pulled from refs of an upstream that
was gone.

What `pull --all` does below, step by step:

| Step | URL in `vendor/a/b/c/.splice` | Fetch | `vendor/a/b/c/` failed? |
| --- | --- | --- | --- |
| Before | `c.git` | | no |
| Pull of `vendor/a/` | `c2.git`, new | fails: `c2.git` is gone | yes |
| Pull of `vendor/a/b/` | | skipped: a splice below it failed | yes |
| Pull of `vendor/a/b/c/` | | skipped: its fetch failed | yes |

The setup takes several steps, because the monorepo must have fetched
`c2.git` once before, so that refs from it are there to be misused.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=5 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1="url.$UPSTREAM-c.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/c.git GIT_CONFIG_KEY_2="url.$UPSTREAM-c2.git.insteadOf" GIT_CONFIG_VALUE_2=https://git.example.com/c2.git GIT_CONFIG_KEY_3=user.name GIT_CONFIG_VALUE_3=Test GIT_CONFIG_KEY_4=user.email GIT_CONFIG_VALUE_4=test@example.com
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_three_levels https://git.example.com/b.git https://git.example.com/c.git
```

## The monorepo fetched a second upstream of `c/` once

A copy of the inner upstream, `c2.git`, gets a commit of its own:

```scrut
$ git clone -q --bare "$UPSTREAM-c.git" "$UPSTREAM-c2.git" &&
>   git clone -q https://git.example.com/c2.git ../c2-work &&
>   echo "c in c2" >>../c2-work/file.txt &&
>   git -C ../c2-work commit -q -am "c in c2" &&
>   git -C ../c2-work push -q origin main
```

The outer upstream points `b/c/` at it:

```scrut
$ git clone -q "$UPSTREAM" ../a-work &&
>   git -C ../a-work config --file b/c/.splice upstream.origin.url https://git.example.com/c2.git &&
>   git -C ../a-work commit -q -am "c from c2" &&
>   git -C ../a-work push -q origin main
```

A pull of `vendor/a/` brings that in, and fetches `c2.git`:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved 5bbd8de..bec105b)
ok   vendor/a/b fetched
ok   vendor/a/b/c fetched
ok   vendor/a: pulled bec105b
ok   vendor/a/b/c fetched
```

Then the outer upstream takes it back, and the monorepo pulls again.
`vendor/a/b/c/` follows `c.git` again, but the fetched refs of `c2.git`,
with `c in c2`, stay:

```scrut
$ git -C ../a-work revert --no-edit HEAD >/dev/null &&
>   git -C ../a-work push -q origin main
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved bec105b..7d63d77)
ok   vendor/a/b fetched
ok   vendor/a/b/c fetched
ok   vendor/a: pulled 7d63d77
ok   vendor/a/b/c fetched
```

## `c2.git` is gone, and the outer upstream points at it again

```scrut
$ mv "$UPSTREAM-c2.git" "$UPSTREAM-c2.gone"
```

```scrut
$ git -C ../a-work revert --no-edit HEAD >/dev/null &&
>   git -C ../a-work push -q origin main
```

The middle upstream changes `c/.splice` too, away from the URL: a
comment on its first line.

```scrut
$ git clone -q https://git.example.com/b.git ../b-work &&
>   sed -i '1i # c, spliced into b' ../b-work/c/.splice &&
>   git -C ../b-work commit -q -am "comment c/.splice" &&
>   git -C ../b-work push -q origin main
```

## `pull --all`

The pull of `vendor/a/` points `vendor/a/b/c/` at `c2.git`, and its
fetch fails. So neither `vendor/a/b/`, whose pull would change
`c/.splice` again, nor `vendor/a/b/c/` is pulled:

```scrut
$ git splice pull --all
ok   vendor/a fetched (main moved 7d63d77..684386f)
ok   vendor/a/b fetched (main moved 8333d5f..c17585f)
ok   vendor/a/b/c fetched
ok   vendor/a: pulled 684386f
fatal: '$UPSTREAM-c2.git' does not appear to be a git repository
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
!!   vendor/a/b/c fetch failed
!!   vendor/a/b: not pulled, since vendor/a/b/c below it failed
!!   vendor/a/b/c: not pulled, since loading the upstream its new .splice names failed
!!   Failed: vendor/a/b/c vendor/a/b
[1]
```

```scrut
$ git log -1 --format=%s
splice: pull vendor/a from main at 684386f
```

```scrut
$ cat vendor/a/b/c/file.txt
c seed
```
