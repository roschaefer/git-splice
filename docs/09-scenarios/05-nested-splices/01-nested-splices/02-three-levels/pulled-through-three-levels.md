# Scenario: nested-splices, three levels: pulled through the levels

`git splice pull vendor/a/b/c` pulls the innermost splice two levels
down: in a worktree of the rebuild of `vendor/a/`, and in there, one of
`b/`. The pull runs in the inner one, as in a clone of the middle
upstream, and its conflict waits there. `git splice pull --continue`
takes the resolved pull up into the outer worktree, and from there into
the monorepo. Each step knows one level only, as the [manual
procedure](https://github.com/roschaefer/git-splice/pull/363) does by
hand.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=4 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1="url.$UPSTREAM-c.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/c.git GIT_CONFIG_KEY_2=user.name GIT_CONFIG_VALUE_2=Test GIT_CONFIG_KEY_3=user.email GIT_CONFIG_VALUE_3=test@example.com
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_three_levels https://git.example.com/b.git https://git.example.com/c.git
```

The inner upstream and the monorepo change the same file:

```scrut
$ git clone -q https://git.example.com/c.git ../c-work &&
>   echo "c upstream" >>../c-work/file.txt &&
>   git -C ../c-work commit -q -am "c upstream" &&
>   git -C ../c-work push -q origin main
```

```scrut
$ echo "c local" >>vendor/a/b/c/file.txt &&
>   git commit -q -am "c local"
```

## The pull

```scrut
$ git splice pull vendor/a/b/c
ok   vendor/a/b/c fetched (main moved 0bfc154..68ea527)
Auto-merging c/file.txt
CONFLICT (content): Merge conflict in c/file.txt
!!   a merge through the levels waits in the worktree of vendor/a/b -- resolve the conflict in .git/splice-layers/d4f300173e760f89, 'git add' it there, then 'git splice pull --continue' (or 'git splice pull --abort')
[1]
```

Two worktrees, one per splice above `vendor/a/b/c/`; the conflict is in
the inner one, at `c/file.txt`:

```scrut
$ git worktree list | wc -l
3
```

```scrut
$ git -C .git/splice-layers/d4f300173e760f89 status --short
M  c/.splice
UU c/file.txt
```

## Resolved, and continued

```scrut
$ printf 'c seed\nc local\nc upstream\n' >.git/splice-layers/d4f300173e760f89/c/file.txt &&
>   git -C .git/splice-layers/d4f300173e760f89 add c/file.txt
```

```scrut
$ git splice pull --continue
ok   vendor/a: took the merge through the levels into the monorepo
```

```scrut
$ git worktree list | wc -l
1
```

A pull of `vendor/a/b/c/` in the monorepo, and all three push, bottom-up:

```scrut
$ git log --format=%s -2
splice: pull vendor/a/b/c from main at 68ea527
c local
```

```scrut
$ git log --graph --format=%s "$(git splice rebuild vendor/a/b/c)"
*   splice: pull vendor/a/b/c from main at 68ea527
|\  
| * c upstream
* | c local
|/  
* c seed
```

```scrut
$ git splice push vendor/a/b/c vendor/a/b vendor/a
ok   vendor/a/b/c: pushed aa77191 to main
ok   vendor/a/b: pushed bdd7318 to main
ok   vendor/a: pushed ca26635 to main
```
