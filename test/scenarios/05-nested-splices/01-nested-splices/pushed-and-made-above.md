# Scenario: nested-splices, pushed and also made in the upstream above

The monorepo pushes a change in `vendor/a/b/` to the inner upstream, but
not `vendor/a/`. Meanwhile, someone makes the same change to `b/` in the
outer upstream, as a commit of their own, along with a change to the
outer upstream's own files. Then the monorepo pulls `vendor/a/`.

The rebuild of `vendor/a/b/` is made from the rebuild of `vendor/a/`
([seen from above](seen-from-above.md)). A push of `vendor/a/` would
leave out the monorepo's commit, since the outer upstream has the same
files. The rebuild keeps it: the inner upstream got it from the push. So the pushed commit
stays in the inner splice's history, the next push goes on top of it,
and the other commit, which only has the same files, doesn't come in.

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

The monorepo changes `vendor/a/b/` and pushes only `vendor/a/b/`:

```scrut
$ echo "b local" >>vendor/a/b/file.txt &&
>   git commit -q -a -m "b local" &&
>   git splice push vendor/a/b
ok   vendor/a/b: pushed 701ab17 to main
```

## The same change, made in the outer upstream

In a clone of the outer upstream, a maintainer makes the same change to
`b/`, and another one to the outer upstream's own files:

```scrut
$ git clone -q "$UPSTREAM" ../a-work &&
>   cd ../a-work &&
>   echo "b local" >>b/file.txt &&
>   git -c user.name=Maintainer -c user.email=maintainer@example.com \
>     commit -q -am "the same change, made in a's upstream" &&
>   echo "a change" >>file.txt &&
>   git commit -q -am "a change" &&
>   git push -q origin HEAD:main &&
>   cd ../monorepo
```

## The monorepo pulls `vendor/a/`

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved ddf42f3..5e4833c)
ok   vendor/a/b fetched
ok   vendor/a: pulled 5e4833c
```

## On a feature branch

The rebuild of `vendor/a/b/` is the inner upstream's `main`. On a branch
the inner upstream doesn't have, `vendor/a/b/` is unchanged, and `push`
creates no branch:

```scrut
$ git switch -q -c feature && git splice status vendor/a/b
On branch feature

  unchanged, no upstream branch  vendor/a/b
```

```scrut
$ git splice push vendor/a/b
ok   vendor/a/b: nothing to push (upstream has no 'feature' branch, and a PR to 'main' would show no changes)
```

```scrut
$ git switch -q main
```

## The next change

The next change to `vendor/a/b/` goes on top of the commit the inner
upstream got from the push: `vendor/a/b/` is ahead by one, not
diverged.

```scrut
$ echo "b next" >>vendor/a/b/file.txt && git commit -q -a -m "b next"
```

```scrut
$ git splice status vendor/a/b
On branch main

  ahead 1  vendor/a/b
```

The push goes on top of `b local`:

```scrut
$ git splice push vendor/a/b
ok   vendor/a/b: pushed b3c7929 to main
```

```scrut
$ git -C "$UPSTREAM-b.git" log --graph --format='%s (%an)' main
* b next (Test)
* b local (Test)
* b seed (Test)
```
