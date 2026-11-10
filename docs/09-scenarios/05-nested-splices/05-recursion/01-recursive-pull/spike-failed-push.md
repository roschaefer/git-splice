# Spike: a failed push below

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=8 GIT_CONFIG_KEY_0="url.$UPSTREAM-a.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git GIT_CONFIG_KEY_1="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/b.git GIT_CONFIG_KEY_2="url.$UPSTREAM-c.git.insteadOf" GIT_CONFIG_VALUE_2=https://git.example.com/c.git GIT_CONFIG_KEY_3="url.$UPSTREAM-d.git.insteadOf" GIT_CONFIG_VALUE_3=https://git.example.com/d.git GIT_CONFIG_KEY_4="url.$UPSTREAM-e.git.insteadOf" GIT_CONFIG_VALUE_4=https://git.example.com/e.git GIT_CONFIG_KEY_5=user.name GIT_CONFIG_VALUE_5=Test GIT_CONFIG_KEY_6=user.email GIT_CONFIG_VALUE_6=test@example.com GIT_CONFIG_KEY_7=core.editor GIT_CONFIG_VALUE_7=true
```
-->

[`setup.bash`](setup.bash)

```scrut
$ build_scenario scenario_recursive_pull
```

```scrut
$ echo "c in the monorepo" >>vendor/a/b/c/file.txt &&
>   git commit -q -am "m1: c in the monorepo"
```

```scrut
$ git clone -q https://git.example.com/c.git ../c-work &&
>   echo "c upstream" >>../c-work/other.txt &&
>   git -C ../c-work add other.txt &&
>   git -C ../c-work commit -q -m "c2: c upstream" &&
>   git -C ../c-work push -q origin main
```

```scrut
$ git splice push --all
To $UPSTREAM-c.git
 ! [rejected]        30bd30abe9a17ddfcf3e4f0626dedab790bc0e07 -> main (fetch first)
error: failed to push some refs to '$UPSTREAM-c.git'
hint: Updates were rejected because the remote contains work that you do not
hint: have locally. This is usually caused by another repository pushing to
hint: the same ref. If you want to integrate the remote changes, use
hint: 'git pull' before pushing again.
hint: See the 'Note about fast-forwards' in 'git push --help' for details.
!!   vendor/a/b/c: push failed
!!   vendor/a/b: not pushed, since vendor/a/b/c below it failed
ok   vendor/a/d: nothing to push
!!   vendor/a: not pushed, since vendor/a/b/c below it failed
!!   Failed: vendor/a/b/c vendor/a/b vendor/a
[1]
```

```scrut
$ git splice push vendor/a/b
ok   vendor/a/b: pushed e879cb1 to main
```

```scrut
$ git -C "$UPSTREAM-b.git" show main:c/.splice | git config --file - splice.commit | cut -c1-7
30bd30a
```

```scrut
$ git -C "$UPSTREAM-c.git" log --format="%h %s" main
5f049ad c2: c upstream
8c169b6 c1: c seed
```

```scrut
$ git log --format="%h %s" "$(git -C "$UPSTREAM-b.git" show main:c/.splice | git config --file - splice.commit)" --
30bd30a m1: c in the monorepo
8c169b6 c1: c seed
```

```scrut
$ git clone -q https://git.example.com/b.git ../b-work && cd ../b-work && git splice fetch c
ok   c fetched
```

```scrut
$ git splice status
??   c: synced commit 30bd30a isn't on main -- made it again here: 8c169b6 and 1 commit of this branch's own
On branch main

  ahead 1, behind 1  c
```

```scrut
$ git splice log c
??   c: synced commit 30bd30a isn't on main -- made it again here: 8c169b6 and 1 commit of this branch's own
===  c (main)
< 30bd30a m1: c in the monorepo  (Test <test@example.com>)
> 5f049ad c2: c upstream  (Test <test@example.com>)
```

```scrut
$ git splice pull --rebase c
ok   c fetched
??   c: synced commit 30bd30a isn't on main -- made it again here: 8c169b6 and 1 commit of this branch's own
!!   c: 'origin' has commits since f815a3c, which --rebase would rewrite -- pull on a branch nobody else has, e.g. a pull request's
!!   Failed: c
[1]
```

```scrut
$ git splice pull c
ok   c fetched
??   c: synced commit 30bd30a isn't on main -- made it again here: 8c169b6 and 1 commit of this branch's own
ok   c: pulled 5f049ad
```

