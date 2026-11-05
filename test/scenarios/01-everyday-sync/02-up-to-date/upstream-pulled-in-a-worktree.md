# Scenario: up-to-date, the upstream pulled in a worktree of the rebuild

[Worked on in a worktree](worked-on-in-a-worktree.md) checks out the
rebuild of `vendor/a/` in a worktree, and `git splice merge
--rebuilt-commit` brings a commit made there back. That merge keeps the
synced commit where it was: whatever the worktree adds counts as the
monorepo's own work, to push.

Here, the worktree pulls `vendor/a/`'s own upstream instead, as one would
in a clone, while the monorepo has a change of its own. That pull's
changes come back as the monorepo's own work too, and the next push
publishes them a second time. `git splice pull vendor/a` in the monorepo
would have recorded the upstream's commit as the synced one instead.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=Test GIT_CONFIG_KEY_1=user.email GIT_CONFIG_VALUE_1=test@example.com
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_up_to_date
```

The upstream gets two commits, *l* and *n*, and the monorepo fetches
them:

```scrut
$ git clone -q "$UPSTREAM" ../a-clone &&
>   echo "first" >>../a-clone/file.txt &&
>   git -C ../a-clone commit -q -am "l: upstream first" &&
>   echo "second" >>../a-clone/file.txt &&
>   git -C ../a-clone commit -q -am "n: upstream second" &&
>   git -C ../a-clone push -q origin main
```

```scrut
$ git splice fetch vendor/a
ok   vendor/a fetched (main moved bde4164..d2c4626)
```

The monorepo changes `vendor/a/`:

```scrut
$ echo "local" >vendor/a/local.txt &&
>   git add vendor/a/local.txt &&
>   git commit -q -m "b: local change"
```

## Pulled in the worktree

```scrut
$ git worktree add -q -b work-on-a ../a-work "$(git splice rebuild vendor/a)"
```

```scrut
$ git -C ../a-work pull -q --no-rebase --no-edit "$UPSTREAM" main
```

The pull merges *n* and the rebuild's copy of *b*, *b'*, in a merge
commit of its own, *w*:

```scrut
$ git -C ../a-work log --graph --format=%s
*   Merge branch 'main' of $UPSTREAM into work-on-a
|\  
| * n: upstream second
| * l: upstream first
* | b: local change
|/  
* seed
```

## Brought back

```scrut
$ git splice merge --rebuilt-commit work-on-a -m "m: merge the worktree" vendor/a
ok   vendor/a: merged [0-9a-f]{7} (regex)
```

The worktree has done its job:

```scrut
$ git worktree remove ../a-work &&
>   git branch -q -D work-on-a
```

<!--
```scrut
$ k="$(git config --file vendor/a/.splice splice.commit)" &&
>   check_drawing "$TESTDIR/upstream-merged-back.drawio.svg" a=HEAD~2 k="$k"
ok   upstream-merged-back.drawio.svg: 8 commits, 11 arrows, 5 boxes, 1 lanes
```
-->

The monorepo has one commit, *m*, with *w*'s changes to *b*: the
upstream's two. *w* is gone with the worktree, and with it that *n* is
its parent: `merge --rebuilt-commit` takes the files of a commit, not its
history.
`.splice` still names *k*, so the rebuild has *m'*, a commit with the
upstream's changes, beside *l* and *n*, the upstream's commits with the
same changes:

<div align="center">

![The monorepo's a, b and m, H at m and B at a; upstream k, l and n, T at n, U(H) at k; the rebuild b prime and m prime on top of k, dashed, R at m prime](upstream-merged-back.drawio.svg)

</div>

The upstream's changes count as local ones, and its commits as missing:

```scrut
$ git log -1 --format=%s "$(git config --file vendor/a/.splice splice.commit)"
seed
```

```scrut
$ git splice status
On branch main

  ahead 2, behind 2  vendor/a
```

```scrut
$ git splice push vendor/a
!!   vendor/a: upstream has commits this branch lacks
!!   Failed: vendor/a
[1]
```

## Pulled, and pushed

```scrut
$ git splice pull vendor/a -m "p: pull vendor/a"
ok   vendor/a fetched
ok   vendor/a: pulled d2c4626
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed bdb6adf to main
```

The upstream has *l* and *n*'s changes twice now: in *l* and *n*, and in
*m'*:

<div align="center">

![The monorepo's a, b, m and the pull p, H at p; upstream k, l and n, U(H) at n; b prime and m prime on top of k, and p prime, a merge of m prime and n, T and R](upstream-pushed-twice.drawio.svg)

</div>

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s main
*   p: pull vendor/a
|\  
| * n: upstream second
| * l: upstream first
* | m: merge the worktree
* | b: local change
|/  
* seed
```

```scrut
$ git -C "$UPSTREAM" show --stat --format=%s main^1
m: merge the worktree

 file.txt | 2 ++
 1 file changed, 2 insertions(+)
```

<!--
```scrut
$ check_drawing "$TESTDIR/upstream-pushed-twice.drawio.svg" \
>   a=HEAD~3 k="$k"
ok   upstream-pushed-twice.drawio.svg: 10 commits, 12 arrows, 3 boxes, 1 lanes
```
-->
