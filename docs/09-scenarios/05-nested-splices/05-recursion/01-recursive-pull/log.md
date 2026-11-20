# Scenario: a recursive pull, logged

An `--exec` hook gets each checkpoint as one line of JSON on its stdin:
the event, and what the pull did and still does for each splice. A hook
that appends it to a file leaves a log of the whole pull, one line per
checkpoint, for a tool like `jq` to read afterwards.

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

## The log

```scrut
$ git splice pull --recursive vendor/a --exec 'cat >>../pull.jsonl'
ok   vendor/a fetched (main moved 764d9c4..6d12ed8)
ok   vendor/a/b fetched (main moved f815a3c..59ed2fb)
ok   vendor/a/b/c fetched (main moved 8c169b6..94cad5e)
ok   vendor/a/d fetched (main moved 2c64d15..36c850e)
ok   vendor/a: pulled 6d12ed8
ok   vendor/a/e fetched
ok   vendor/a/e: nothing to pull
ok   vendor/a/b: pulled 59ed2fb
ok   vendor/a/b/c: pulled 94cad5e
ok   vendor/a/d: pulled 36c850e
ok   vendor/a: 4 pulls made one commit, 9b51e79
```

One line per checkpoint, each an event with its name:

```scrut
$ jq -r '[.event.name, .event.path // empty] | join(" ")' ../pull.jsonl
after-fetch
after-merge vendor/a
after-fetch
after-merge vendor/a/b
after-merge vendor/a/b/c
after-merge vendor/a/d
before-fold
after-fold
```

The line after `b/`'s merge, with the commits left out:

```scrut
$ jq 'select(.event.name == "after-merge" and .event.path == "vendor/a/b") | del(.event.head_before, .event.head_after)' ../pull.jsonl
{
  "event": {
    "name": "after-merge",
    "path": "vendor/a/b"
  },
  "tasks": {
    "splices": [
      {
        "path": "vendor/a",
        "task": "done"
      },
      {
        "path": "vendor/a/b",
        "task": "done"
      },
      {
        "path": "vendor/a/b/c",
        "task": "pending",
        "step": "merge"
      },
      {
        "path": "vendor/a/d",
        "task": "pending",
        "step": "merge"
      },
      {
        "path": "vendor/a/e",
        "task": "done"
      }
    ],
    "next": null
  }
}
```

`tasks.splices` lists each splice top-down: `vendor/a/` and `b/` are
done, and so is `e/`, which `a`'s merge brought in with nothing to pull;
`c/` and `d/` wait for their merge. `next` names a step beyond the
splices, where there is one:

```scrut
$ jq -r 'select(.tasks.next) | .event.name + ": " + .tasks.next' ../pull.jsonl
before-fold: fold
after-fold: clean up
```

`head_before` and `head_after` are the monorepo's `HEAD` before and
after the merge, so `git log` shows what it committed:

```scrut
$ git log --format=%s "$(jq -r 'select(.event.name == "after-merge" and .event.path == "vendor/a/b") | .event.head_before + ".." + .event.head_after' ../pull.jsonl)"
splice: pull vendor/a/b from main at 59ed2fb
```

The fold's commit replaced those of the merges:

```scrut
$ git log --oneline --format=%s -1
splice: pull vendor/a from main at 6d12ed8
```
