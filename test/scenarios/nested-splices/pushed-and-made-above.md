# Scenario: nested-splices, pushed and also made in the upstream above

The monorepo pushes a change in b to b's upstream, but not a. Meanwhile,
someone makes the same change to b in a's upstream, as a commit of their
own, along with a change to a. Then the monorepo pulls a.

Up to the pull, b's history comes from a's upstream
([spliced elsewhere](spliced-elsewhere.md)): the other commit, which
has the same files as the monorepo's b after the pull. But the
monorepo's own history has the commit b's upstream got from its push,
which a's upstream doesn't. So the rebuild joins both: b's upstream is
in b's history, and a push of b goes on top of it. Before, the rebuild
dropped the pushed commit, since b's files didn't differ from a's
upstream, and b read as diverged after its next change.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1=Test GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=test@example.com
```
-->

[`setup.bash`](setup.bash) builds the state of the [README](README.md):
a with b spliced in at `b/`, cloned into the monorepo:

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

The monorepo changes b and pushes only b:

```scrut
$ echo "b local" >>vendor/a/b/file.txt && git commit -q -a -m "b local" && git splice push vendor/a/b
ok   vendor/a/b: pushed 701ab17 to main
```

## The same change, made in a's upstream

In a clone of a's upstream, a maintainer makes the same change to b, and
another one to a:

```scrut
$ git clone -q "$UPSTREAM" ../a-work && cd ../a-work && echo "b local" >>b/file.txt && git -c user.name=Maintainer -c user.email=maintainer@example.com commit -q -am "the same change, made in a's upstream" && echo "a change" >>file.txt && git commit -q -am "a change" && git push -q origin HEAD:main && cd ../monorepo
```

## The monorepo pulls a

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved da334c3..2e5cd72)
ok   vendor/a/b fetched
ok   vendor/a: pulled 2e5cd72
```

b's files are the same as in a's upstream. The next change to b goes on
top of the commit b's upstream got from the push: b is ahead, not
diverged. Ahead by three: the maintainer's commit, the pull that joins
it in, and `b next`.

```scrut
$ echo "b next" >>vendor/a/b/file.txt && git commit -q -a -m "b next"
```

```scrut
$ git splice status vendor/a/b
ok   vendor/a/b -> main (push: ahead 3)
```

The push joins the maintainer's commit in, which b's upstream didn't
have yet, and goes on top of `b local`:

```scrut
$ git splice push vendor/a/b
ok   vendor/a/b: pushed bb6d650 to main
```

```scrut
$ git -C "$UPSTREAM-b.git" log --graph --format='%s (%an)' main
* b next (Test)
*   splice: pull vendor/a from main at 2e5cd72 (Test)
|\  
| * the same change, made in a's upstream (Maintainer)
* | b local (Test)
|/  
* b seed (Test)
```
