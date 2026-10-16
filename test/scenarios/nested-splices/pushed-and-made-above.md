# Scenario: nested-splices, pushed and also made in the upstream above

The monorepo pushes a change in `vendor/a/b/` to the inner upstream, but
not `vendor/a/`. Meanwhile, someone makes the same change to `b/` in the
outer upstream, as a commit of their own, along with a change to the
outer upstream's own files. Then the monorepo pulls `vendor/a/`.

Up to the pull, the history of `vendor/a/b/` comes from the outer
upstream ([spliced elsewhere](spliced-elsewhere.md)): the other commit,
which has the same files as the monorepo's `vendor/a/b/` after the pull.
But the monorepo's own history has the commit the inner upstream got
from its push, which the outer upstream doesn't. So the rebuild joins
both: the inner upstream is in the inner splice's history, and a push of
`vendor/a/b/` goes on top of it. Before, the rebuild dropped the pushed
commit, since the inner splice's files didn't differ from the outer
upstream's, and `vendor/a/b/` read as diverged after its next change.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1=Test GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=test@example.com
```
-->

[`setup.bash`](setup.bash) builds the state of the [README](README.md):
the outer upstream with the inner one spliced in at `b/`, cloned into
the monorepo:

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

The monorepo changes `vendor/a/b/` and pushes only `vendor/a/b/`:

```scrut
$ echo "b local" >>vendor/a/b/file.txt && git commit -q -a -m "b local" && git splice push vendor/a/b
ok   vendor/a/b: pushed 701ab17 to main
```

## The same change, made in the outer upstream

In a clone of the outer upstream, a maintainer makes the same change to
`b/`, and another one to the outer upstream's own files:

```scrut
$ git clone -q "$UPSTREAM" ../a-work && cd ../a-work && echo "b local" >>b/file.txt && git -c user.name=Maintainer -c user.email=maintainer@example.com commit -q -am "the same change, made in a's upstream" && echo "a change" >>file.txt && git commit -q -am "a change" && git push -q origin HEAD:main && cd ../monorepo
```

## The monorepo pulls `vendor/a/`

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved ddf42f3..5e4833c)
ok   vendor/a/b fetched
ok   vendor/a: pulled 5e4833c
```

The files of `vendor/a/b/` are the same as in the outer upstream. The
next change to `vendor/a/b/` goes on top of the commit the inner
upstream got from the push: `vendor/a/b/` is ahead, not diverged. Ahead
by three: the maintainer's commit, the pull that joins it in, and
`b next`.

```scrut
$ echo "b next" >>vendor/a/b/file.txt && git commit -q -a -m "b next"
```

```scrut
$ git splice status vendor/a/b
On branch main

  ahead 3  vendor/a/b
```

The push joins the maintainer's commit in, which the inner upstream
didn't have yet, and goes on top of `b local`:

```scrut
$ git splice push vendor/a/b
ok   vendor/a/b: pushed d599698 to main
```

```scrut
$ git -C "$UPSTREAM-b.git" log --graph --format='%s (%an)' main
* b next (Test)
*   splice: pull vendor/a from main at 5e4833c (Test)
|\  
| * the same change, made in a's upstream (Maintainer)
* | b local (Test)
|/  
* b seed (Test)
```
