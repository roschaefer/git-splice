# Scenario: nested-splices, pulled through the levels

`git splice pull vendor/a/b` pulls the inner splice one level at a time:
it checks out the rebuild of `vendor/a/` in a worktree, the repository
`vendor/a/b/` is spliced into, pulls `b` there as in a clone of the outer
upstream, and takes the result back into `vendor/a/` with `git splice
merge --rebuilt-commit`. Without a conflict, that's all one command, and
the worktree is gone again.

A conflict waits in the worktree, like a rebase in progress: `status`
says so, the splices it's for refuse other pulls, merges and pushes, and
`git splice pull --continue` takes the resolved result into the monorepo.
The monorepo itself is free meanwhile.

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

The inner upstream and the monorepo change the same file:

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

## The pull

```scrut
$ git splice pull vendor/a/b
ok   vendor/a/b fetched (main moved 11f4ee8..66aab4e)
Auto-merging b/file.txt
CONFLICT (content): Merge conflict in b/file.txt
!!   a merge through the levels waits in the worktree of vendor/a -- resolve the conflict in .git/splice-layers/main/vendor%a, 'git add' it there, then 'git splice pull --continue' (or 'git splice pull --abort')
[1]
```

The conflict is in the worktree, at `b/file.txt`:

```scrut
$ git -C .git/splice-layers/main/vendor%a status --short
M  b/.splice
UU b/file.txt
```

The monorepo's working tree has nothing of it, and `status` says what
waits:

```scrut
$ git status --short
```

```scrut
$ git splice status
On branch main

  a merge through the levels waits in the worktree of vendor/a -- resolve the conflict in .git/splice-layers/main/vendor%a, 'git add' it there, then 'git splice pull --continue' (or 'git splice pull --abort')
  ahead 1, behind 1  vendor/a/b
  ahead 1            vendor/a
```

```scrut
$ git splice push vendor/a/b
!!   a merge through the levels waits in the worktree of vendor/a -- resolve the conflict in .git/splice-layers/main/vendor%a, 'git add' it there, then 'git splice pull --continue' (or 'git splice pull --abort')
[1]
```

## Resolved, and continued

```scrut
$ printf 'b seed\nb local\nb upstream\n' >.git/splice-layers/main/vendor%a/b/file.txt &&
>   git -C .git/splice-layers/main/vendor%a add b/file.txt
```

```scrut
$ git splice pull --continue
ok   vendor/a: took the merge through the levels into the monorepo
```

A pull of `vendor/a/b/`, as if the monorepo had pulled it itself: the
pull's commit, `.splice` naming the inner upstream's commit, and a
rebuild that joins both changes:

```scrut
$ git log --format=%s -2
splice: pull vendor/a/b from main at 66aab4e
b local
```

```scrut
$ git log --graph --format=%s "$(git splice rebuild vendor/a/b)"
*   splice: pull vendor/a/b from main at 66aab4e
|\  
| * b upstream
* | b local
|/  
* b seed
```

```scrut
$ git splice push vendor/a/b
ok   vendor/a/b: pushed 294c70c to main
```

The worktree and its branch are gone:

```scrut
$ git worktree list | wc -l
1
```
