# Scenario: diverged-common-ancestor

Both sides changed the same line since the clone.

- **Monorepo (`vendor/a/`)**: *a* clones *k* (`seed`), then *b* (`local change`) changes the folder.
- **Upstream**: *k*, then *l* (`upstream change`), already fetched.

<div align="center">

![The monorepo commit a clones the upstream commit k, then b changes the folder; the upstream has l on top of k, T, and the rebuild b prime on top of k, R, dashed](diverged.drawio.svg)

</div>

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_diverged_common_ancestor
```

<!--
```scrut
$ k="$(git config --file vendor/a/.splice splice.commit)" &&
>   check_drawing "$TESTDIR/diverged.drawio.svg" k="$k" a=HEAD~1 b=HEAD l=splices/upstream/heads/main
ok   diverged.drawio.svg: 5 commits, 6 arrows, 3 boxes, 1 lanes
```
-->

```scrut
$ git splice status
On branch main

  ahead 1, behind 1  vendor/a
```

```scrut
$ git splice log
===  vendor/a (main)
< e859a6b local change  (Test <test@example.com>)
> 6045a98 upstream change  (Test <test@example.com>)
```

`push` refuses: upstream has a commit this branch lacks.

```scrut
$ git splice push vendor/a
!!   vendor/a: upstream has commits this branch lacks -- run 'git splice pull vendor/a' first
!!   Failed: vendor/a
[1]
```

`merge` stops at the conflict, like any merge:

```scrut
$ git splice merge vendor/a
Auto-merging vendor/a/file.txt
CONFLICT (content): Merge conflict in vendor/a/file.txt
!!   vendor/a: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)
!!   vendor/a: merge failed
!!   Failed: vendor/a
[1]
```

Resolve it and commit as usual:

```scrut
$ git status --short
M  vendor/a/.splice
UU vendor/a/file.txt
```

```scrut
$ printf 'seed\nlocal change\nupstream change\n' >vendor/a/file.txt &&
>   git add vendor/a/file.txt &&
>   git commit -q --no-edit
```

Upstream gets the local commit, joined with its own by a merge:

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 7f55741 to main
```

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s main
*   splice: merge vendor/a from main at 6045a98
|\  
| * upstream change
* | local change
|/  
* seed
```
