# Scenario: nested-splices, continued after a change meanwhile

While a pull's conflict waits in the worktree of `vendor/a/`
([waiting in a worktree](waiting-in-a-worktree.md)), the monorepo is
free, and here it changes the same lines of `vendor/a/b/file.txt` once
more. `git splice pull --continue` takes the resolved pull up into the
monorepo with a three-way merge, `git splice merge --rebuilt-commit`, so
that change stays. Here it conflicts with the pull, and the conflict
lands in the monorepo's working tree, like any other: resolved there,
and concluded with `git commit`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1=Test GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=test@example.com
```
-->

[`setup.bash`](setup.bash) builds the state of the [README](README.md):

```scrut
$ build_scenario scenario_nested_splices https://git.example.com/b.git
```

The inner upstream and the monorepo change the same file, and the pull
conflicts one level down:

```scrut
$ git clone -q https://git.example.com/b.git ../b-work &&
>   echo "b upstream" >>../b-work/file.txt &&
>   git -C ../b-work commit -q -am "b upstream" &&
>   git -C ../b-work push -q origin main
```

```scrut
$ echo "b local" >>vendor/a/b/file.txt &&
>   git commit -q -am "b local"
```

```scrut
$ git splice pull vendor/a/b >/dev/null 2>&1
[1]
```

## A change meanwhile

```scrut
$ echo "b meanwhile" >>vendor/a/b/file.txt &&
>   git commit -q -am "b meanwhile"
```

## Resolved one level down, and continued

```scrut
$ printf 'b seed\nb local\nb upstream\n' >.git/splice-layers/fb2b0b3ec7fa189a/b/file.txt &&
>   git -C .git/splice-layers/fb2b0b3ec7fa189a add b/file.txt
```

```scrut
$ git splice pull --continue
Auto-merging vendor/a/b/file.txt
CONFLICT (content): Merge conflict in vendor/a/b/file.txt
!!   vendor/a: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)
[1]
```

The worktree is gone; the conflict with the change meanwhile is in the
monorepo now:

```scrut
$ git worktree list | wc -l
1
```

```scrut
$ git status --short
M  vendor/a/b/.splice
UU vendor/a/b/file.txt
```

```scrut
$ printf 'b seed\nb local\nb meanwhile\nb upstream\n' >vendor/a/b/file.txt &&
>   git add vendor/a/b/file.txt &&
>   git commit -q --no-edit
```

## A pull, with the change meanwhile

```scrut
$ git log --format=%s -3
splice: pull vendor/a/b from main at 66aab4e
b meanwhile
b local
```

```scrut
$ git log --graph --format=%s "$(git splice rebuild vendor/a/b)"
*   splice: pull vendor/a/b from main at 66aab4e
|\  
| * b upstream
* | b meanwhile
* | b local
|/  
* b seed
```

```scrut
$ git splice push vendor/a/b
ok   vendor/a/b: pushed 3b9c383 to main
```
