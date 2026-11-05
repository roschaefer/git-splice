# Scenario: nested-splices, pulled in a worktree of the splice above

`git splice pull vendor/a/b` merges the inner upstream straight into the
monorepo's folder, and a conflict lands in the monorepo's working tree.
This page does the same pull one level down, by hand:

<div align="center">

![The monorepo, with the splice vendor/a/ and inside it vendor/a/b/; next to it a worktree of vendor/a/ rebuilt, with the splice b/; 1: rebuild vendor/a and add the worktree; 2: pull b from the upstream of b into the worktree, where the conflict is resolved; 3: copy the worktree back into vendor/a/ with git archive; 4: push vendor/a/b from the monorepo to the upstream of b](pulled-in-a-layer.drawio.svg)

</div>

In the worktree, `b/` is a splice like any other, with no nesting. The
conflict comes up there, and its resolution is a commit of that
repository. Copied back into `vendor/a/`, it's a pull of `vendor/a/b/`
to the monorepo too: the rebuild and the push are the same as after a
pull in the monorepo.

[Rebuilt layer by layer](rebuilt-in-layers.md) shows where running the
commands per level goes wrong for the rebuild.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=4 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1=Test GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=test@example.com GIT_CONFIG_KEY_3=core.editor GIT_CONFIG_VALUE_3=true
```
-->

[`setup.bash`](setup.bash) builds the state of the [README](README.md):

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

The inner upstream and the monorepo change the same file:

```scrut
$ git clone -q https://git.example.com/b.git ../b-work &&
>   echo "b upstream" >>../b-work/file.txt &&
>   git -C ../b-work commit -q -am "b upstream" &&
>   git -C ../b-work push -q origin main
```

```scrut
$ echo "b local" >>vendor/a/b/file.txt &&
>   git commit -q -a -m "b local"
```

```scrut
$ git splice fetch vendor/a vendor/a/b
ok   vendor/a fetched
ok   vendor/a/b fetched (main moved 11f4ee8..66aab4e)
```

## The pull, one level down

The rebuild of `vendor/a/`, checked out in a worktree of the monorepo. It
shares the monorepo's fetched refs, so the inner upstream is there:

```scrut
$ git worktree add -q -b layer/a ../a-layer "$(git splice rebuild vendor/a)" &&
>   cd ../a-layer
```

```scrut
$ git log --format=%s
b local
add b
a seed
```

A worktree can't have `main` checked out too, so `--branch` names the
inner upstream's branch. The conflict comes up in this repository:

```scrut
$ git splice pull --branch main b
ok   b fetched
Auto-merging b/file.txt
CONFLICT (content): Merge conflict in b/file.txt
!!   b: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)
!!   b: pull failed
!!   Failed: b
[1]
```

```scrut
$ printf 'b seed\nb local\nb upstream\n' >b/file.txt &&
>   git add b/file.txt &&
>   git cherry-pick --continue
[layer/a 6582d33] splice: pull b from main at 66aab4e
 Date: Thu Jan 1 00:00:00 2026 +0000
 2 files changed, 2 insertions(+), 1 deletion(-)
```

```scrut
$ git log --format=%s -1
splice: pull b from main at 66aab4e
```

## Back into the monorepo

`vendor/a/` gets the worktree's files, and keeps its own `.splice`, which
the rebuild doesn't have:

```scrut
$ cd ../monorepo &&
>   git rm -q -r -- vendor/a ':!vendor/a/.splice' &&
>   git archive layer/a | tar -x -C vendor/a &&
>   git add vendor/a &&
>   git commit -q -m "$(git log -1 --format=%s layer/a)"
```

The commit changes `vendor/a/b/.splice`, so it's a pull of `vendor/a/b/`
to the monorepo: its rebuild joins the local change and the inner
upstream's, as after a pull in the monorepo, and the push sends that:

```scrut
$ git splice status vendor/a/b
On branch main

  ahead 2  vendor/a/b
```

```scrut
$ git log --graph --format=%s "$(git splice rebuild vendor/a/b)"
*   splice: pull b from main at 66aab4e
|\  
| * b upstream
* | b local
|/  
* b seed
```

```scrut
$ git splice push vendor/a/b
ok   vendor/a/b: pushed d91986f to main
```
