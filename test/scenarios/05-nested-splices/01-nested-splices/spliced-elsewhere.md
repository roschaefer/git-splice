# Scenario: nested-splices, spliced into another monorepo

The monorepo pushes a change in `vendor/a/b/`, the splice below
`vendor/a/`. Then another monorepo splices the outer upstream in. There,
the inner splice's files already have the change, but its `.splice`
still names the synced commit from before it, and `git splice clone`
squashed the outer upstream's history into one commit: the other
monorepo's own history has nothing between that synced commit and the
inner splice's files.

The outer upstream has that history, though, and the other monorepo
fetched it. So up to the clone, the inner splice's history is rebuilt
from the outer upstream: the rebuild gets exactly the commit the first
monorepo pushed, the inner splice is up to date, and its first change is
pushed on top. Before, it read as diverged there, and `pull` conflicted
on a line both sides had
([#74](https://github.com/roschaefer/git-splice/issues/74)).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1=Other GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=other@example.com
```
-->

[`setup.bash`](setup.bash) builds the state of the [README](README.md):
the outer upstream with the inner one spliced in at `b/`, cloned into
the monorepo:

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

The monorepo changes `vendor/a/b/` and pushes both, bottom-up:

```scrut
$ echo "b local" >>vendor/a/b/file.txt && git commit -q -a -m "b local" && git splice push vendor/a/b vendor/a
ok   vendor/a/b: pushed f47c373 to main
ok   vendor/a: pushed 924e6e3 to main
```

`vendor/a/b/.splice` still names the synced commit from before the
change: a push writes nothing to the monorepo. The push of `vendor/a/`
publishes this `.splice`, along with a commit `b local` in the outer
upstream:

```scrut
$ git -C "$UPSTREAM" show main:b/.splice | git config --file - splice.commit | xargs git -C "$UPSTREAM-b.git" log -1 --format=%s
b seed
```

## Another monorepo splices the outer upstream in

```scrut
$ git init -q -b main ../other && cd ../other && git commit -q --allow-empty -m "other monorepo"
```

```scrut
$ git splice clone "$UPSTREAM" vendor/a && git splice fetch
===  vendor/a: fetching $UPSTREAM
ok   vendor/a: cloned 924e6e3 from main
ok   vendor/a fetched
ok   vendor/a/b fetched
```

`clone` squashed the outer upstream's history into one commit. The files
of `vendor/a/b/` there already have `b local`, but its `.splice` names
`b seed`:

```scrut
$ git log --format=%s
splice: clone vendor/a from main at 924e6e3
other monorepo
```

```scrut
$ cat vendor/a/b/file.txt; git log -1 --format=%s "$(git config --file vendor/a/b/.splice splice.commit)"
b seed
b local
b seed
```

Up to date, since the inner splice's files match the inner upstream:

```scrut
$ git splice status
On branch main

  up to date  vendor/a
  up to date  vendor/a/b
```

The first change to `vendor/a/b/` here:

```scrut
$ echo "b other" >>vendor/a/b/file.txt && git commit -q -a -m "b other"
```

The rebuild of `vendor/a/b/` reads its history up to the clone in the
outer upstream, where `b local` is a commit of its own. So it gets the
commit the first monorepo pushed, and only `b other` is new:

```scrut
$ git splice status vendor/a/b
On branch main

  ahead 1  vendor/a/b
```

```scrut
$ git splice log vendor/a/b
===  vendor/a/b (main)
< f123e09 b other  (Other <other@example.com>)
```

There's nothing to pull, and the push goes on top of `b local`:

```scrut
$ git splice pull vendor/a/b
ok   vendor/a/b fetched
ok   vendor/a/b: nothing to pull
```

```scrut
$ git splice push vendor/a/b
ok   vendor/a/b: pushed f123e09 to main
```

```scrut
$ git -C "$UPSTREAM-b.git" log --format=%s main
b other
b local
b seed
```
