# Spike

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
$ echo "a in the monorepo" >>vendor/a/file.txt &&
>   echo "b in the monorepo" >>vendor/a/b/notes.txt &&
>   echo "c in the monorepo" >>vendor/a/b/c/file.txt &&
>   git add vendor/a && git commit -q -m "m1: a, b and c in the monorepo"
```

```scrut
$ git splice push --all
ok   vendor/a/b/c: pushed c36e473 to main
ok   vendor/a/b: pushed 5302c23 to main
ok   vendor/a/d: nothing to push
ok   vendor/a: pushed 04ebbea to main
```

```scrut
$ git status --short; git diff | head -20
```

```scrut
$ git -C "$UPSTREAM-b.git" show main:c/.splice | git config --file - splice.commit | cut -c1-7 &&
>   git -C "$UPSTREAM-c.git" rev-parse --short main
c36e473
c36e473
```

```scrut
$ git -C "$UPSTREAM-a.git" show main:b/.splice | git config --file - splice.commit | cut -c1-7 &&
>   git -C "$UPSTREAM-b.git" rev-parse --short main
5302c23
5302c23
```

```scrut
$ git -C "$UPSTREAM-a.git" show main:b/c/.splice | git config --file - splice.commit | cut -c1-7
c36e473
```

```scrut
$ git splice status
On branch main

  up to date  vendor/a
  up to date  vendor/a/b
  up to date  vendor/a/b/c
  up to date  vendor/a/d
```

```scrut
$ git clone -q https://git.example.com/a.git ../a-work && cd ../a-work && git splice status
On branch main

  ?? never fetched  b    run 'git splice fetch b'
  ?? never fetched  b/c  run 'git splice fetch b/c'
  ?? never fetched  d    run 'git splice fetch d'
```

```scrut
$ git splice pull --all
ok   b fetched
ok   d fetched
ok   b/c fetched
ok   b: nothing to pull
ok   b/c: nothing to pull
ok   d: nothing to pull
```

```scrut
$ cd ../monorepo && git splice pull --all
ok   vendor/a fetched
ok   vendor/a/b fetched
ok   vendor/a/b/c fetched
ok   vendor/a/d fetched
ok   vendor/a: nothing to pull
ok   vendor/a/b: nothing to pull
ok   vendor/a/b/c: nothing to pull
ok   vendor/a/d: nothing to pull
```

```scrut
$ echo "c again" >>vendor/a/b/c/file.txt && git commit -q -am "m2: c again" && git splice push --all
ok   vendor/a/b/c: pushed 3830d27 to main
ok   vendor/a/b: pushed e99151a to main
ok   vendor/a/d: nothing to push
ok   vendor/a: pushed a0972a4 to main
```

```scrut
$ git -C "$UPSTREAM-a.git" show main:b/c/.splice | git config --file - splice.commit | cut -c1-7 &&
>   git -C "$UPSTREAM-b.git" show main:c/.splice | git config --file - splice.commit | cut -c1-7 &&
>   git -C "$UPSTREAM-c.git" rev-parse --short main
3830d27
3830d27
3830d27
```

```scrut
$ git splice status
On branch main

  up to date  vendor/a
  up to date  vendor/a/b
  up to date  vendor/a/b/c
  up to date  vendor/a/d
```

```scrut
$ git clone -q https://git.example.com/c.git ../c-work && echo "c upstream" >>../c-work/file.txt && git -C ../c-work commit -q -am "c3: c upstream" && git -C ../c-work push -q origin main
```

```scrut
$ git clone -q https://git.example.com/b.git ../b-work && cd ../b-work && git splice pull c && git push -q origin main && cd ../monorepo
ok   c fetched
ok   c: pulled b207cc4
```

```scrut
$ git splice pull --all
ok   vendor/a fetched
ok   vendor/a/b fetched (main moved e99151a..ce98b2c)
ok   vendor/a/b/c fetched (main moved 3830d27..b207cc4)
ok   vendor/a/d fetched
ok   vendor/a: nothing to pull
ok   vendor/a/b: pulled ce98b2c
ok   vendor/a/b/c: nothing to pull
ok   vendor/a/d: nothing to pull
[0]
```

```scrut
$ git splice status
On branch main

  ahead 1     vendor/a

  up to date  vendor/a/b
  up to date  vendor/a/b/c
  up to date  vendor/a/d
```

```scrut
$ git splice push --all
ok   vendor/a/b/c: nothing to push
ok   vendor/a/b: nothing to push
ok   vendor/a/d: nothing to push
ok   vendor/a: pushed b6eb13e to main
```
