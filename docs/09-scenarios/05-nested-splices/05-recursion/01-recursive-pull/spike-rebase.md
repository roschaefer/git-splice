# Spike: pull --rebase where the record is ahead of the upstream

With the spike, a rebuild records each splice inside it at its own
rebuild. Here `c`'s push is rejected, `b` is pushed anyway, so `b`'s
upstream records `c` at *m1'*, a commit `c`'s upstream doesn't have. In a
clone of `b`'s upstream, `pull --rebase c` then has two choices of sync
point: *m1'*, as recorded, or *c1*, the newest commit in its history that
`c`'s upstream has. Only the second keeps *m1*'s change.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=8 GIT_CONFIG_KEY_0="url.$UPSTREAM-a.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git GIT_CONFIG_KEY_1="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/b.git GIT_CONFIG_KEY_2="url.$UPSTREAM-c.git.insteadOf" GIT_CONFIG_VALUE_2=https://git.example.com/c.git GIT_CONFIG_KEY_3="url.$UPSTREAM-d.git.insteadOf" GIT_CONFIG_VALUE_3=https://git.example.com/d.git GIT_CONFIG_KEY_4="url.$UPSTREAM-e.git.insteadOf" GIT_CONFIG_VALUE_4=https://git.example.com/e.git GIT_CONFIG_KEY_5=user.name GIT_CONFIG_VALUE_5=Test GIT_CONFIG_KEY_6=user.email GIT_CONFIG_VALUE_6=test@example.com GIT_CONFIG_KEY_7=core.editor GIT_CONFIG_VALUE_7=true
```
-->


[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_recursive_pull
```

The monorepo changes `c/`, in *m1*:

```scrut
$ echo "c in the monorepo" >>vendor/a/b/c/file.txt &&
>   git commit -q -am "m1: c in the monorepo"
```

Meanwhile `c`'s upstream gets *c2*:

```scrut
$ git clone -q https://git.example.com/c.git ../c-work &&
>   echo "c upstream" >>../c-work/other.txt &&
>   git -C ../c-work add other.txt &&
>   git -C ../c-work commit -q -m "c2: c upstream" &&
>   git -C ../c-work push -q origin main
```

`c`'s push is rejected; `b`'s goes through anyway:

```scrut
$ git splice push vendor/a/b/c
To $UPSTREAM-c.git
 ! [rejected]        30bd30abe9a17ddfcf3e4f0626dedab790bc0e07 -> main (fetch first)
error: failed to push some refs to '$UPSTREAM-c.git'
hint: Updates were rejected because the remote contains work that you do not
hint: have locally. This is usually caused by another repository pushing to
hint: the same ref. If you want to integrate the remote changes, use
hint: 'git pull' before pushing again.
hint: See the 'Note about fast-forwards' in 'git push --help' for details.
!!   vendor/a/b/c: push failed
!!   Failed: vendor/a/b/c
[1]
```

```scrut
$ git splice push vendor/a/b
ok   vendor/a/b: pushed e879cb1 to main
```

## In a clone of `b`'s upstream

```scrut
$ git clone -q https://git.example.com/b.git ../b-work &&
>   cd ../b-work &&
>   git splice fetch c
ok   c fetched
```

`status` makes the synced commit again, from *m1'* and the record
before it, *c1*: the same rebuild gives the same commit:

```scrut
$ git splice status
??   c: synced commit 30bd30a isn't on main -- made it again here: 8c169b6 and 1 commit of this branch's own
On branch main

  ahead 1, behind 1  c
```

Its newest commit is *m1'*, `b`'s copy of *m1*. It changed `c/file.txt`
and records `c` at the copy of *m1* in `c`'s history, which `c`'s upstream
lacks:

```scrut
$ git log --format=%s -2
m1: c in the monorepo
b1: add c
```

```scrut
$ git config --file c/.splice splice.commit | cut -c1-7
30bd30a
```

```scrut
$ git log --format=%s "$(git config --file c/.splice splice.commit)"
m1: c in the monorepo
c1: c seed
```

```scrut
$ git log --format=%s splices/c/heads/main
c2: c upstream
c1: c seed
```

`pull --rebase` refuses:

```scrut
$ git splice pull --rebase c
ok   c fetched
??   c: synced commit 30bd30a isn't on main -- made it again here: 8c169b6 and 1 commit of this branch's own
!!   c: 'origin' has commits since f815a3c, which --rebase would rewrite -- pull on a branch nobody else has, e.g. a pull request's
!!   Failed: c
[1]
```

## With *m1'* as the sync point

The sync point is the last commit where `c/` has the synced commit's
files: *m1'* itself. A `--rebase` pull puts *c2*'s files on top of it,
and replays what comes after it: nothing. Done by hand:

```scrut
$ git switch -q -c at-m1 &&
>   git rm -r -q c &&
>   git read-tree -u --prefix=c/ splices/c/heads/main &&
>   git show main:c/.splice >c/.splice &&
>   git config --file c/.splice splice.commit "$(git rev-parse splices/c/heads/main)" &&
>   git add c/.splice &&
>   git commit -q -m "pull c at c2"
```

*m1*'s line is gone from `c/file.txt`, in a commit that only says it
pulls *c2*:

```scrut
$ cat c/file.txt
c1: c seed
```

```scrut
$ git diff --stat main at-m1 -- c
 c/.splice   | 2 +-
 c/file.txt  | 1 -
 c/other.txt | 1 +
 3 files changed, 2 insertions(+), 2 deletions(-)
```

## With *c1* as the sync point

*c1* is the newest commit in the synced commit's history that `c`'s
upstream has:

```scrut
$ git log --format=%s -1 "$(git merge-base "$(git config --blob main:c/.splice splice.commit)" splices/c/heads/main)"
c1: c seed
```

The last commit where `c/` has *c1*'s files is the one before *m1'*.
*c2*'s files go on top of it, then *m1'* is replayed:

```scrut
$ git switch -q -c at-c1 main~1 &&
>   git rm -r -q c &&
>   git read-tree -u --prefix=c/ splices/c/heads/main &&
>   git show main~1:c/.splice >c/.splice &&
>   git config --file c/.splice splice.commit "$(git rev-parse splices/c/heads/main)" &&
>   git add c/.splice &&
>   git commit -q -m "pull c at c2" &&
>   git cherry-pick main >/dev/null 2>&1
[1]
```

Replaying *m1'* conflicts in `c/.splice` only: *m1'* moved the record
from *c1*, and the pull from *c1* to *c2*. The record stays at *c2*:

```scrut
$ git checkout -q --ours c/.splice &&
>   git add c/.splice &&
>   git cherry-pick --continue >/dev/null
```

*m1*'s line is kept, on top of *c2*:

```scrut
$ cat c/file.txt
c1: c seed
c in the monorepo
```

```scrut
$ git log --format=%s -3
m1: c in the monorepo
pull c at c2
b1: add c
```

