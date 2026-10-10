# The same name above and below

Both splices name an upstream `fork`, each its company's fork of its own
upstream. Names are unique only within one `.splice`, so `--upstream
fork` means a's fork for `vendor/a/` and b's fork for `vendor/a/b/`
([#107](https://github.com/roschaefer/git-splice/issues/107)).

[`setup.bash`](setup.bash) builds the state of [outer-fork](README.md).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1="url.$UPSTREAM-fork.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/company/a.git GIT_CONFIG_KEY_2="url.$UPSTREAM-b-fork.git.insteadOf" GIT_CONFIG_VALUE_2=https://git.example.com/company/b.git
```
-->

```scrut
$ build_scenario scenario_outer_fork https://git.example.com/b.git
```

Each `.splice` gets its own fork, and keeps its upstream as the default:

```scrut
$ git config --file vendor/a/.splice upstream.fork.url https://git.example.com/company/a.git && git config --file vendor/a/.splice splice.default-upstream origin
```

```scrut
$ git config --file vendor/a/b/.splice upstream.fork.url https://git.example.com/company/b.git && git config --file vendor/a/b/.splice splice.default-upstream origin
```

```scrut
$ git commit -q -m "add the company forks" -- vendor/a/.splice vendor/a/b/.splice
```

```scrut
$ git splice fetch
ok   vendor/a fetched from origin
ok   vendor/a fetched from fork
ok   vendor/a/b fetched from origin
ok   vendor/a/b fetched from fork
```

```scrut
$ git splice status --upstream fork
ok   vendor/a -> fork/main (diverged: ahead 1, behind 1)
ok   vendor/a/b -> fork/main (pull: behind 1)
```

### Pulling each from its fork

Top-down, as every pull: a's fork's patch to `b/` first, then b's
fork's patch. Since `vendor/a/b` is selected too, its `fork` is b's
fork, and it's fetched from that one only:

```scrut
$ git splice pull --upstream fork --all
ok   vendor/a fetched from fork
ok   vendor/a/b fetched from fork
ok   vendor/a: pulled 697c854
ok   vendor/a/b: pulled d5d5b62
```

```scrut
$ git splice status --upstream fork
ok   vendor/a -> fork/main (push: ahead 3)
ok   vendor/a/b -> fork/main (push: ahead 2)
```

```scrut
$ git splice status
ok   vendor/a -> origin/main (push: ahead 4)
ok   vendor/a/b -> origin/main (push: ahead 3)
```

### The default travels with the `.splice`

The push of `vendor/a` publishes I's `.splice` with the rest of its
folder. Its `default-upstream` goes along, so in a's upstream, `b/`
pulls and pushes by default where it does in the monorepo:

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 38831eb to origin/main
```

```scrut
$ git -C "$UPSTREAM" show main:b/.splice | tr '\t' ' '
[splice]
 commit = d5d5b62373ad5b94d1393019ab51f2ad34bb43c2
 id = b260547af9afae07
 default-upstream = origin
[upstream "origin"]
 url = https://git.example.com/b.git
[upstream "fork"]
 url = https://git.example.com/company/b.git
```
