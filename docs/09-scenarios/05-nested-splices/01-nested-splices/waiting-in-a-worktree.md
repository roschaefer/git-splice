# Scenario: nested-splices, a conflict waiting in a worktree

A pull of `vendor/a/b` runs one level down, in a worktree of the rebuild
of `vendor/a/` ([pulled through the levels](pulled-through-the-levels.md)).
That worktree doesn't see uncommitted changes, so the pull refuses them
up front. A conflict waits in the worktree, as a rebase in progress
does: until `--continue` or `--abort`, the splices it's for refuse
other pulls, merges and pushes, while the monorepo is free otherwise.
`--abort` gives up, and nothing reaches the monorepo.

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

## Uncommitted changes first

A change to `vendor/a/` that isn't committed yet stops the pull before it
starts:

```scrut
$ echo "uncommitted" >>vendor/a/file.txt
```

```scrut
$ git splice pull vendor/a/b
!!   vendor/a has uncommitted changes, which a pull through the levels wouldn't see -- commit or stash them first
!!   Failed: vendor/a/b
[1]
```

```scrut
$ git checkout -q -- vendor/a/file.txt
```

## The conflict waits

```scrut
$ git splice pull vendor/a/b
ok   vendor/a/b fetched (main moved 11f4ee8..66aab4e)
Auto-merging b/file.txt
CONFLICT (content): Merge conflict in b/file.txt
!!   a merge through the levels waits in the worktree of vendor/a -- resolve the conflict in .git/splice-layers/fb2b0b3ec7fa189a, 'git add' it there, then 'git splice pull --continue' (or 'git splice pull --abort')
[1]
```

`vendor/a/b` and `vendor/a`, whose worktree has the conflict, refuse
other commands until it's concluded:

```scrut
$ git splice push vendor/a/b
!!   a merge through the levels waits in the worktree of vendor/a -- resolve the conflict in .git/splice-layers/fb2b0b3ec7fa189a, 'git add' it there, then 'git splice pull --continue' (or 'git splice pull --abort')
[1]
```

```scrut
$ git splice pull vendor/a
!!   a merge through the levels waits in the worktree of vendor/a -- resolve the conflict in .git/splice-layers/fb2b0b3ec7fa189a, 'git add' it there, then 'git splice pull --continue' (or 'git splice pull --abort')
[1]
```

The rest of the monorepo is free, `vendor/a/` too:

```scrut
$ echo "a meanwhile" >vendor/a/other.txt &&
>   git add vendor/a/other.txt &&
>   git commit -q -m "a meanwhile"
```

## Giving up

```scrut
$ git splice pull --abort
ok   vendor/a: merge through the levels aborted -- nothing reached the monorepo
```

The worktree and its branch are gone, and the monorepo has only its own
commits:

```scrut
$ git worktree list | wc -l
1
```

```scrut
$ git branch --list 'splice-layer/*'
```

```scrut
$ git log --format=%s -2
a meanwhile
b local
```

```scrut
$ git splice status vendor/a/b
On branch main

  ahead 1, behind 1  vendor/a/b
```
