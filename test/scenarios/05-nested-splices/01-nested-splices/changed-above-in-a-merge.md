# Scenario: nested-splices, changed above, in a merge

The monorepo changes `vendor/a/b/` and doesn't push it. Meanwhile, a
maintainer changes `b/` in the outer upstream. The monorepo's pull of
`vendor/a/` then merges both, and the rebuild of `vendor/a/`, the
[view](seen-from-above.md) of `vendor/a/b/`, gets a merge.

A rebuild turns a merge into one commit. So the rebuild of `vendor/a/b/`
gets the maintainer's change in the pull's commit, under the pull's
author: the maintainer's own commit isn't in it. A clone of the outer
upstream, after the monorepo pushed both, rebuilds `b/` the same way,
so the inner splice is up to date there: it doesn't matter where it
syncs from.

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
>   git commit -q -m "b local"
```

In a clone of the outer upstream, a maintainer changes `b/` too:

```scrut
$ git clone -q "$UPSTREAM" ../a-work &&
>   cd ../a-work &&
>   echo "b in a's upstream" >>b/file.txt &&
>   git -c user.name=Maintainer -c user.email=maintainer@example.com \
>     commit -q -am "b in a's upstream" &&
>   git push -q origin HEAD:main &&
>   cd ../monorepo
```

The monorepo pulls `vendor/a/`, which merges both changes:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved * (glob)
ok   vendor/a/b fetched
ok   vendor/a: pulled * (glob)
```

<div align="center">

![The monorepo commits a, c and p; in the lane vendor/a/, the upstream commits k, l and n, and the dashed c prime and p prime, where p prime merges c prime and n and is R; in the lane vendor/a/b/, the upstream commit m, and the dashed c prime and p prime on top of it, where p prime has one parent and is R](changed-above-in-a-merge.drawio.svg)

</div>

*c* (`b local`) is the monorepo's change, *n* (`b in a's upstream`) the
maintainer's, and *p* the pull. In `vendor/a/`, the view R is *p'*, a
merge of *c'* and *n*. In `vendor/a/b/`, R is *p'* too, but with one
parent: *n* has no copy there, its change is in *p'*.

<!--
```scrut
$ check_drawing "$TESTDIR/changed-above-in-a-merge.drawio.svg" \
>   a=HEAD~2 c=HEAD~1 p=HEAD k=refs/splices/upstream/heads/main~2 \
>   l=refs/splices/upstream/heads/main~1 n=refs/splices/upstream/heads/main \
>   m=refs/splices/b/heads/main
ok   changed-above-in-a-merge.drawio.svg: 11 commits, 14 arrows, 5 boxes, 2 lanes
```
-->

## The view has the merge

The rebuild of `vendor/a/` has `b local` on one side, the maintainer's
commit on the other, and the pull that joins them:

```scrut
$ git log --graph --format='%s (%an)' "$(git splice rebuild vendor/a)"
*   splice: pull vendor/a from main at 7228f0e (Test)
|\  
| * b in a's upstream (Maintainer)
* | b local (Test)
|/  
* add b (Test)
* a seed (Test)
```

## The inner splice has one commit for it

The rebuild of `vendor/a/b/` follows the view's first parents, as any
rebuild follows the monorepo's. The maintainer's change comes in with the
pull, under its author:

```scrut
$ git log --graph --format='%s (%an)' "$(git splice rebuild vendor/a/b)"
* splice: pull vendor/a from main at 7228f0e (Test)
* b local (Test)
* b seed (Test)
```

## The same from a clone of the outer upstream

The monorepo pushes both, bottom-up:

```scrut
$ git splice push vendor/a/b vendor/a
ok   vendor/a/b: pushed * to main (glob)
ok   vendor/a: pushed * to main (glob)
```

In a clone of the outer upstream, `b/` is a splice of its own, and its
rebuild is the commit the inner upstream got from the monorepo:

```scrut
$ git clone -q "$UPSTREAM" ../a-clone &&
>   cd ../a-clone &&
>   git splice fetch b
ok   b fetched
```

```scrut
$ git splice status b
On branch main

  up to date  b
```
