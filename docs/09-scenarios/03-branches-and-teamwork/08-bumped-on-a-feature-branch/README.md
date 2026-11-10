# Scenario: bumped-on-a-feature-branch

[Bumping the sync point](../../../04-advanced-workflows/03-bump.md#when-not-to-bump)
says not to bump on a feature branch. This shows why, when the library
squash-merges its pull requests: a bump on a feature branch that's merged
after the library's merge conflicts, and one merged before leaves `main`
naming a commit that disappears.

It starts after a push on `main` and a bump there, *a*. The push sent
*k* (`local change`).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_bumped_on_a_feature_branch &&
>   MONOREPO="$PWD" && MAINTAINER="$(dirname "$PWD")/maintainer"
```

### Merged after the library: a conflict

A feature that changes the library and the monorepo's code that uses it:

```scrut
$ git switch -q -c feature
```

```scrut
$ echo "an option" >>vendor/a/file.txt &&
>   mkdir -p app &&
>   echo "uses the option" >app/main.txt &&
>   git add app &&
>   git commit -qam "b: an option in vendor/a, and the app uses it"
```

The push creates the upstream's `feature` branch, the library's pull
request. A bump then records it on the monorepo's `feature`:

```scrut
$ git splice push vendor/a
??   vendor/a: upstream has no 'feature' branch yet -- this push creates it
ok   vendor/a: pushed 72ab783 to feature
```

```scrut
$ git splice pull --bump -m "c: bump vendor/a to the pull request" vendor/a
ok   vendor/a fetched
ok   vendor/a: bumped the synced commit to 72ab783
```

The library squash-merges the pull request: its `main` gets the same
change as a new commit. Here in a clone of the upstream, as its
maintainer would:

```scrut
$ git clone -q "$UPSTREAM" "$MAINTAINER" &&
>   cd "$MAINTAINER" &&
>   git config user.name "Maintainer" &&
>   git config user.email "maintainer@example.com"
```

```scrut
$ git merge -q --squash origin/feature &&
>   git commit -q -m "s: an option (#1)" &&
>   git push -q origin main
Squash commit -- not updating HEAD
```

Back in the monorepo, `main` pulls it:

```scrut
$ cd "$MONOREPO" && git switch -q main
```

```scrut
$ git splice pull -m "d: pull the squashed option" vendor/a
ok   vendor/a fetched (main moved e859a6b..2380a33)
ok   vendor/a: pulled 2380a33
```

*b'* is *b* as pushed:

<div align="center">

![The monorepo commits a and d on main, and b and c on feature, both from a; in the lane vendor/a/, s on main and b prime on feature, both on top of k; U(d) is s and U(c) is b prime](bump-conflict.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/bump-conflict.drawio.svg" \
>   b=feature~1 c=feature k=refs/splices/upstream/heads/main~1
ok   bump-conflict.drawio.svg: 7 commits, 9 arrows, 4 boxes, 1 lanes
```
-->

`main` has the library's change now, but not the app's. So the monorepo's
`feature` still needs merging, and that conflicts: *d*'s `.splice`
records *s*, and *c*'s the same line as *b'*. A squash merge computes its
files like any merge, so it conflicts too:

```scrut
$ git merge --squash feature
Auto-merging vendor/a/.splice
CONFLICT (content): Merge conflict in vendor/a/.splice
Squash commit -- not updating HEAD
Automatic merge failed; fix conflicts and then commit the result.
[1]
```

```scrut
$ git reset -q --hard
```

Without the bump, `feature` wouldn't have changed `.splice`, and the merge
would take `main`'s.

### The way out: rebase the library's branch

Rebase the library's `feature` onto its `main`. The squashed commit
already has the change, so the rebase drops it, and `feature` becomes the
library's `main`:

```scrut
$ cd "$MAINTAINER" &&
>   git switch -q feature &&
>   git -c advice.skippedCherryPicks=false rebase -q main &&
>   git push -q -f origin feature
```

```scrut
$ git log -1 --format=%s feature
s: an option (#1)
```

The monorepo's `feature` pulls it. The folder already has its files, so
`pull` records it, without the need for `--bump`:

```scrut
$ cd "$MONOREPO" && git switch -q feature
```

```scrut
$ git splice pull -m "e: record the squashed option" vendor/a
ok   vendor/a fetched (feature moved 72ab783..2380a33)
ok   vendor/a: recorded 2380a33 as the synced commit -- the folder already has its files
```

*e* names *s*, as `main`'s *d* does:

<div align="center">

![The same graphs after the rebase: e on top of c on feature records s, which is now both main and feature of the library](bump-way-out.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/bump-way-out.drawio.svg" \
>   d=main b=feature~2 c=feature~1 e=feature k=refs/splices/upstream/heads/main~1
ok   bump-way-out.drawio.svg: 7 commits, 8 arrows, 3 boxes, 1 lanes
```
-->

Now both branches name the same commit in `.splice`, and the merge only
brings in the app:

```scrut
$ git switch -q main && git merge --squash feature
Automatic merge went well; stopped before committing as requested
Squash commit -- not updating HEAD
```

```scrut
$ git status --short
A  app/main.txt
```

```scrut
$ git commit -q -m "app: use vendor/a's option" && git splice status
On branch main

  up to date  vendor/a
```

If the library deleted its `feature` branch after the merge, there's
nothing to pull. Merge `main` into the monorepo's `feature` instead, and
resolve `.splice` to `main`'s version.

### Merged before the library: a commit that disappears

Another feature, with a bump on its branch. This time, `main` merges it
before the library merges its pull request:

```scrut
$ git switch -q -c feature-2 &&
>   echo "a second option" >>vendor/a/file.txt &&
>   git commit -qam "vendor/a: a second option"
```

```scrut
$ git splice push vendor/a >/dev/null && git splice pull --bump vendor/a
ok   vendor/a fetched
ok   vendor/a: bumped the synced commit to 52ca126
```

```scrut
$ git switch -q main && git merge -q --no-ff -m "Merge branch 'feature-2'" feature-2
```

`main`'s `.splice` now names a commit of the library's `feature-2`:

```scrut
$ git log -1 --format=%s "$(git config --file vendor/a/.splice splice.commit)"
vendor/a: a second option
```

The library squash-merges the pull request and deletes its branch, as
many hosts do:

```scrut
$ cd "$MAINTAINER" &&
>   git fetch -q &&
>   git switch -q main &&
>   git merge -q --squash origin/feature-2 &&
>   git commit -q -m "a second option (#2)" &&
>   git push -q origin main :feature-2
Squash commit -- not updating HEAD
```

Then it goes on with a change of its own:

```scrut
$ echo "a third option" >>file.txt &&
>   git commit -qam "a third option" &&
>   git push -q origin main
```

Nothing refers to the pull request's commit any more, and the library's
`gc` removes it:

```scrut
$ git -C "$UPSTREAM" gc -q --prune=now &&
>   synced="$(git -C "$MONOREPO" config --file vendor/a/.splice splice.commit)" &&
>   git -C "$UPSTREAM" cat-file -t "$synced"
fatal: git cat-file: could not get object info
[128]
```

The monorepo that bumped still has the commit, but a fresh clone of it
can't fetch it:

```scrut
$ cd "$(dirname "$MONOREPO")" &&
>   git clone -q "file://$MONOREPO" colleague &&
>   cd colleague &&
>   git config user.name "Colleague" &&
>   git config user.email "colleague@example.com"
```

```scrut
$ git splice fetch vendor/a
ok   vendor/a fetched
```

```scrut
$ git splice status vendor/a
??   vendor/a: synced commit 52ca126 isn't on main -- made it again here: 2380a33 and 1 commit of this branch's own
On branch main

  ahead 1, behind 2  vendor/a
```

It makes the commit again instead: the rebuild of the commit before the
bump gives *52ca126*, hash included. Only a copy of the monorepo's own
history comes out the same, so the part the library's `main` lacks counts
as the monorepo's own, `vendor/a: a second option`, which `log` shows
next to the library's two commits:

```scrut
$ git splice log vendor/a
??   vendor/a: synced commit 52ca126 isn't on main -- made it again here: 2380a33 and 1 commit of this branch's own
===  vendor/a (main)
= 52ca126 vendor/a: a second option  (Test <test@example.com>)
> 460ece3 a third option  (Maintainer <maintainer@example.com>)
= 5e19ac3 a second option (#2)  (Maintainer <maintainer@example.com>)
```

`pull --rebase` refuses. The commits of the monorepo's own start below
its last sync, the bump: replaying them would replay the bump too, and
its record would meet the pull's. Doing that, and going on after a
conflict, needs a pull that carries its state from one run to the next
([#446](https://github.com/roschaefer/git-splice/pull/446)):

```scrut
$ git splice pull --rebase vendor/a
ok   vendor/a fetched
??   vendor/a: synced commit 52ca126 isn't on main -- made it again here: 2380a33 and 1 commit of this branch's own
!!   vendor/a: synced commit 52ca126 was made again here -- --rebase doesn't replay what's above 2380a33; pull without --rebase
!!   Failed: vendor/a
[1]
```

A plain pull merges them instead. Both sides added the same line after
`an option`, and the library one more, so the merge conflicts there:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
??   vendor/a: synced commit 52ca126 isn't on main -- made it again here: 2380a33 and 1 commit of this branch's own
Auto-merging vendor/a/file.txt
CONFLICT (content): Merge conflict in vendor/a/file.txt
!!   vendor/a: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)
!!   vendor/a: pull failed
!!   Failed: vendor/a
[1]
```

```scrut
$ cat vendor/a/file.txt
seed
local change
an option
a second option
<<<<<<< HEAD
=======
a third option
>>>>>>> * (splice: pull vendor/a from main at 460ece3) (glob)
```

Taking the library's side resolves it:

```scrut
$ git checkout -q --theirs vendor/a/file.txt &&
>   git add vendor/a/file.txt &&
>   git commit -q --no-edit
```

```scrut
$ git splice status vendor/a
On branch main

  up to date  vendor/a
```

The folder has the files of the library's `main` now, so nothing is left
to push, and the second option isn't sent again. Without the bump,
`main`'s `.splice` would name a commit on the library's `main`, which it
keeps, and a pull would bring in `a third option` without a conflict.

A splice moved after the bump isn't made again yet
([moved after the bump](moved-after-the-bump.md)).
