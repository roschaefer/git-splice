# Scenario: a recursive pull, with its progress

A recursive pull can take a while. An `--exec` hook gets each checkpoint
as JSON on its stdin, with each splice's task, so it can say how far the
pull got.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=8 GIT_CONFIG_KEY_0="url.$UPSTREAM-a.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git GIT_CONFIG_KEY_1="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/b.git GIT_CONFIG_KEY_2="url.$UPSTREAM-c.git.insteadOf" GIT_CONFIG_VALUE_2=https://git.example.com/c.git GIT_CONFIG_KEY_3="url.$UPSTREAM-d.git.insteadOf" GIT_CONFIG_VALUE_3=https://git.example.com/d.git GIT_CONFIG_KEY_4="url.$UPSTREAM-e.git.insteadOf" GIT_CONFIG_VALUE_4=https://git.example.com/e.git GIT_CONFIG_KEY_5=user.name GIT_CONFIG_VALUE_5=Test GIT_CONFIG_KEY_6=user.email GIT_CONFIG_VALUE_6=test@example.com GIT_CONFIG_KEY_7=core.editor GIT_CONFIG_VALUE_7=true
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_recursive_pull
```

Each upstream moves on, and `a`'s splices `e` in:

```scrut
$ for x in b c d; do
>   git clone -q "https://git.example.com/$x.git" "../$x-work" &&
>     echo "$x upstream" >>"../$x-work/file.txt" &&
>     git -C "../$x-work" commit -q -am "${x}2: $x upstream" &&
>     git -C "../$x-work" push -q origin main
> done
```

```scrut
$ git clone -q https://git.example.com/a.git ../a-work &&
>   cd ../a-work &&
>   git splice clone https://git.example.com/e.git e >/dev/null &&
>   echo "a upstream" >>file.txt &&
>   git commit -q --amend -am "a2: a upstream, and e spliced in" &&
>   git push -q origin main &&
>   cd ../monorepo
```

## The progress

[`progress.sh`](progress.sh) counts the splices whose task is `done`:

```scrut
$ export PROGRESS="$TESTDIR/progress.sh" && cat "$PROGRESS"
#!/bin/sh
# A hook for 'git splice pull --exec': prints at each checkpoint how many
# splices the pull is done with, from the JSON on its stdin.
jq -r '([.event.name, .event.path // empty] | join(" "))
  + ": \([.tasks.splices[] | select(.task == "done")] | length)"
  + " of \(.tasks.splices | length) done"'
```

`after-fetch` comes twice: `a`'s merge brought in `e/`, which the pull
then fetched. `e/` had nothing to pull, so it's done before `b/`:

```scrut
$ git splice pull --recursive vendor/a --exec 'sh "$PROGRESS"'
ok   vendor/a fetched (main moved 764d9c4..6d12ed8)
ok   vendor/a/b fetched (main moved f815a3c..59ed2fb)
ok   vendor/a/b/c fetched (main moved 8c169b6..94cad5e)
ok   vendor/a/d fetched (main moved 2c64d15..36c850e)
after-fetch: 0 of 4 done
ok   vendor/a: pulled 6d12ed8
after-merge vendor/a: 1 of 4 done
ok   vendor/a/e fetched
after-fetch: 1 of 5 done
ok   vendor/a/e: nothing to pull
ok   vendor/a/b: pulled 59ed2fb
after-merge vendor/a/b: 3 of 5 done
ok   vendor/a/b/c: pulled 94cad5e
after-merge vendor/a/b/c: 4 of 5 done
ok   vendor/a/d: pulled 36c850e
after-merge vendor/a/d: 5 of 5 done
before-fold: 5 of 5 done
ok   vendor/a: 4 pulls made one commit, 9b51e79
after-fold: 5 of 5 done
```

The [log](log.md) shows the JSON in full.
