# `git subtree`'s sync points are in commit messages

`git subtree` keeps no file of its own. With `--squash` and `--rejoin`,
the sync point that keeps `split` fast
([`--rejoin`](rejoin.md)) is a set of lines in commit messages, found
by the folder's name. So two ordinary operations break it: a squash
merge that copies those lines into another commit, and a `git mv` of
the folder.

The setup: [the comparisons' library and monorepo](../README.md), with
the library added with `--squash`, two fixes, and a `split --rejoin`.
The branch `squash-merged` has the fixes squash-merged, as a host does
with a pull request:

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../scrut-setup.sh"
```
-->

```scrut
$ git switch -q -c squashed &&
>   git subtree add -q --squash --prefix=vendor/lib https://git.example.com/lib.git main >/dev/null &&
>   echo "app commit 41" >>app/main.txt && git commit -q -a -m "app commit 41" &&
>   echo "lib fix 1" >>vendor/lib/src/parse.txt && git commit -q -a -m "lib fix 1" &&
>   echo "app commit 42" >>app/main.txt && git commit -q -a -m "app commit 42" &&
>   echo "lib fix 2" >>vendor/lib/src/parse.txt && git commit -q -a -m "lib fix 2" &&
>   git subtree split -q --rejoin --squash --prefix=vendor/lib >/dev/null &&
>   git switch -q -c squash-merged "squashed^~4" &&
>   git merge -q --squash squashed >/dev/null &&
>   git commit -q -m "lib fixes (#1)"
```

## The lines

Each commit that `--squash` and `--rejoin` make ends in lines that name
the folder and the library commit it matches. *r*, the squashed changes
from the rejoin:

```scrut
$ git log -1 --format=%B squashed^2
Squashed 'vendor/lib/' changes from bafd496..48108da

48108da lib fix 2
0579a80 lib fix 1

git-subtree-dir: vendor/lib
git-subtree-split: 48108daa0f798109c3e672ed47a7de6204cf4e02

```

The merge *j* names its monorepo side as well, in a third line,
`git-subtree-mainline:`. To find the newest sync point, `pull --squash`
and `split` search the commits reachable from `HEAD` with `git log
--grep="^git-subtree-dir: vendor/lib/*$"`. So a sync point belongs to
whatever folder name the message has, and to whichever commit carries
the message.

## A squash merge copies them into another commit

Hosts can fill a squash merge's message with the messages of the pull
request's commits. Then *p*, the squash commit, carries the lines of *j*
and *r*:

```scrut
$ git commit -q --amend -m "lib fixes (#1)" \
>   -m "$(git log --format='* %s%n%n%b' HEAD~1..squashed)"
```

```scrut
$ git log -1 --format=%B | grep '^git-subtree-'
git-subtree-dir: vendor/lib
git-subtree-mainline: 9d3cc6061455cb38432ce9846218e1227e4771be
git-subtree-split: 48108daa0f798109c3e672ed47a7de6204cf4e02
git-subtree-dir: vendor/lib
git-subtree-split: 48108daa0f798109c3e672ed47a7de6204cf4e02
```

*p* is no commit `git subtree` made. The newest message names a
monorepo side, so `pull --squash` takes *p* for a `--rejoin` merge and
asks for its second parent, which *p* doesn't have:

```scrut
$ git subtree pull -q --squash --prefix=vendor/lib https://git.example.com/lib.git main
From $COMPARISON/upstream/lib
 * branch            main       -> FETCH_HEAD
fatal: Needed a single revision

[1]
```

## A moved folder loses them

Back on the branch with the rejoin, the library moves to
`vendor/parser/`:

```scrut
$ git switch -q squashed &&
>   git mv vendor/lib vendor/parser && git commit -q -m "move vendor/lib to vendor/parser"
```

The messages still say `vendor/lib`, so under the new name there's no
sync point:

```scrut
$ git subtree pull -q --squash --prefix=vendor/parser https://git.example.com/lib.git main
From $COMPARISON/upstream/lib
 * branch            main       -> FETCH_HEAD
fatal: can't squash-merge: 'vendor/parser' was never added.
[1]
```

And under the old one, there's no folder:

```scrut
$ git subtree pull -q --squash --prefix=vendor/lib https://git.example.com/lib.git main
fatal: 'vendor/lib' does not exist; use 'git subtree add'
[1]
```

`split` walks the monorepo's whole history again:

```scrut
$ subtree_split_walks vendor/parser
49
```

Before the move there was no `vendor/parser/`, so the history it builds
starts at the move, without the library's:

```scrut
$ git subtree split --prefix=vendor/parser --branch=parser-split >/dev/null &&
>   git log --format=%s parser-split
move vendor/lib to vendor/parser
```

The library's `main` doesn't lead there, so `push` is refused:

```scrut
$ git subtree push --prefix=vendor/parser https://git.example.com/lib.git main | grep -F '[rejected]'
 ! [rejected]        c7121590d05f5a17f3adebbbd88ff15816a537d2 -> main (non-fast-forward)
```

## In `git-splice`

The sync point is in `vendor/lib/.splice`, a file in the folder, not in
a commit message
([the same sync point, kept in a file](../git-subtree.md#the-same-sync-point-kept-in-a-file)).
A squash merge [keeps it](../../scenarios/03-branches-and-teamwork/03-squash-merged-pull/README.md),
`git mv` moves it along, and a change to it shows in the diff like any
other change. Moving a splice has gaps of its own, shown in the
[moved folders scenarios](../../scenarios/07-moved-folders/01-moved-with-unpushed-commits/README.md).
