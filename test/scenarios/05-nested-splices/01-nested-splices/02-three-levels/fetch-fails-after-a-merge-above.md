# Scenario: nested-splices, three levels: a failed fetch, cleared by the next merge

A pull of the outer splice can change the `.splice` of the inner one,
and the pull fetches the upstream the new file names. If that fetch
fails, the inner splice isn't merged in this command: what an earlier
fetch of that upstream left could be stale.

The middle splice's pull, in the same command, can change the inner
`.splice` again. Then `pull` reads it once more, and if that works, it
forgets the failure. Here that's wrong: the middle splice changes another
line, the second read finds the URL it already read, and fetches nothing. So the inner
splice is merged from the upstream that failed to fetch, from what an
earlier fetch left.

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
fetch fails. The pull of `vendor/a/b/` changes `c/.splice` again, and
the second read finds `c2.git`, which it read before, so it doesn't
fetch. That clears the failure, and `vendor/a/b/c/` is pulled from the
refs left from before:

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
ok   vendor/a/b: pulled c17585f
ok   vendor/a/b/c: pulled f8b34aa
```

```scrut
$ git log -1 --format=%s
splice: pull vendor/a/b/c from main at f8b34aa
```

```scrut
$ cat vendor/a/b/c/file.txt
c seed
c in c2
```
