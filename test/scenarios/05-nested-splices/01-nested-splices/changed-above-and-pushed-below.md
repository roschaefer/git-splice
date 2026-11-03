# Scenario: nested-splices, changed above and pushed below

As in [changed above, in a merge](changed-above-in-a-merge.md), the
monorepo changes `vendor/a/b/` without pushing it, and a maintainer
changes `b/` in the outer upstream. There, the maintainer's commit
isn't in the inner splice's history: the rebuild follows first parents
only.

This time the maintainer pushes `b/` to the inner upstream first, and
records that push in `b/.splice`, before pushing the outer upstream.
Then the inner
upstream has the commit, and the monorepo's pull of `vendor/a/` is a
pull of `vendor/a/b/` too: its rebuild joins the maintainer's commit, as
any pull joins the synced commit.

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

The monorepo changes `vendor/a/b/`, and doesn't push it:

```scrut
$ echo "b local" >vendor/a/b/local.txt &&
>   git add vendor/a/b/local.txt &&
>   git commit -q -m "c: b local"
```

In a clone of the outer upstream, a maintainer changes `b/` too:

```scrut
$ git clone -q "$UPSTREAM" ../a-work &&
>   cd ../a-work &&
>   echo "b in a's upstream" >>b/file.txt &&
>   git -c user.name=Maintainer -c user.email=maintainer@example.com \
>     commit -q -am "n: b in a's upstream"
```

## The maintainer pushes `b/` first

`b/` is a splice in the clone, so the maintainer can push it to the
inner upstream:

```scrut
$ git splice fetch b && git splice push b
ok   b fetched
ok   b: pushed * to main (glob)
```

A push writes nothing to the clone, so `b/.splice` still records the
inner upstream's commit from before. `pull --bump` records the pushed
one, with a commit of its own, and the maintainer pushes the outer
upstream:

```scrut
$ git splice pull --bump b
ok   b fetched
ok   b: bumped the synced commit to * (glob)
```

```scrut
$ git push -q origin HEAD:main && cd ../monorepo
```

## The monorepo pulls `vendor/a/`

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved * (glob)
ok   vendor/a/b fetched (main moved * (glob)
ok   vendor/a: pulled * (glob)
```

<div align="center">

![The monorepo commits a, c and p, where H and main point at p; in the lane vendor/a/, the upstream commits k, l, n and q, where main points at q, and the dashed c prime and p prime, where p prime merges c prime and q and is R; in the lane vendor/a/b/, the upstream commits m and n prime, where main points at n prime, and the dashed c double prime and p double prime, where p double prime merges c double prime and n prime and is R](changed-above-and-pushed-below.drawio.svg)

</div>

*q* is the maintainer's bump. In `vendor/a/b/`, *n'* is the inner
upstream's copy of *n*, from the maintainer's push, and *q*'s
`b/.splice` records it. The monorepo's pull brings that `.splice` in, so
for `vendor/a/b/` it's a pull too: *p''* is a join of *c''* and *n'*,
and the maintainer's commit is in the history.

<!--
```scrut
$ check_drawing "$TESTDIR/changed-above-and-pushed-below.drawio.svg" \
>   a=HEAD~2 p=HEAD k=refs/splices/upstream/heads/main~3 \
>   l=refs/splices/upstream/heads/main~2 n=refs/splices/upstream/heads/main~1 \
>   q=refs/splices/upstream/heads/main m=refs/splices/b/heads/main~1
ok   changed-above-and-pushed-below.drawio.svg: 13 commits, 17 arrows, 5 boxes, 2 lanes
```
-->

```scrut
$ git log --graph --format='%s (%an)' "$(git splice rebuild vendor/a/b)"
*   splice: pull vendor/a from main at 319b60d (Test)
|\  
| * n: b in a's upstream (Maintainer)
* | c: b local (Test)
|/  
* b seed (Test)
```

Neither splice diverged: each is ahead by *c* and *p*.

```scrut
$ git splice status
On branch main

  ahead 2  vendor/a
  ahead 2  vendor/a/b
```

The push sends the maintainer's commit along, as a parent of the join:

```scrut
$ git splice push vendor/a/b vendor/a
ok   vendor/a/b: pushed * to main (glob)
ok   vendor/a: pushed * to main (glob)
```

```scrut
$ git -C "$UPSTREAM-b.git" log --graph --format='%s (%an)' main
*   splice: pull vendor/a from main at 319b60d (Test)
|\  
| * n: b in a's upstream (Maintainer)
* | c: b local (Test)
|/  
* b seed (Test)
```

Without the bump, the inner upstream would have *n'* while the monorepo
still synced with *m*: `vendor/a/b/` would be ahead 2 and behind 1, and
a pull of `vendor/a/b/` in the monorepo would join *n'* then.
