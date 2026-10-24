# The same name above and below

Both splices name an upstream `fork`, each its company's fork of its own
upstream. Names are unique only within one `.splice`, so
`--upstream fork` means the outer fork for `vendor/a/` and the inner
fork for `vendor/a/b/`
([#107](https://github.com/roschaefer/git-splice/issues/107)).

[`setup.bash`](setup.bash) builds the state of [outer-fork](README.md).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1="url.$UPSTREAM-fork.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/company/a.git GIT_CONFIG_KEY_2="url.$UPSTREAM-b-fork.git.insteadOf" GIT_CONFIG_VALUE_2=https://git.example.com/company/b.git
```
-->

```scrut
$ build_scenario scenario_outer_fork https://git.example.com/b.git
```

Each `.splice` gets its own fork, and keeps its upstream as the default:

```scrut
$ git config --file vendor/a/.splice upstream.fork.url https://git.example.com/company/a.git &&
>   git config --file vendor/a/.splice splice.default-upstream origin
```

```scrut
$ git config --file vendor/a/b/.splice upstream.fork.url https://git.example.com/company/b.git &&
>   git config --file vendor/a/b/.splice splice.default-upstream origin
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
On branch main

  ahead 1, behind 1  vendor/a -> fork/main
  behind 1           vendor/a/b -> fork/main
```

Both lanes are split, and each has a `fork` side, of a different fork.
The outer fork has *q* (`a fork patch to b`) on top of *k* (`a seed`)
and *l* (`add b`); the inner fork has *n* (`b fork patch`) on top of *m*
(`b seed`). *c* (`add the company forks`) changed `vendor/a/b/.splice`,
a file of `vendor/a/` too, so R of `vendor/a/` is *c'*, its copy on top
of *l*, which no upstream has yet:

<div align="center">

![The monorepo's a and c, H; the lane vendor/a/ split in two: origin with c prime, dashed, which is R, on top of l on top of k, l being T, U(H) and U(B); fork with q on top of l on top of k, its main; inside it, the lane vendor/a/b/, also split: origin with m, which is T, R, U(H) and U(B); fork with n on top of m, its main](same-name-below.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/same-name-below.drawio.svg" \
>   a=HEAD~1 c=HEAD k=refs/splices/upstream/heads/main~1 l=refs/splices/upstream/heads/main \
>   q=refs/splices/a/heads/main m=refs/splices/b/heads/main n=refs/splices/company-b/heads/main
ok   same-name-below.drawio.svg: 11 commits, 12 arrows, 6 boxes, 2 lanes, 4 upstreams
```
-->

### Pulling each from its fork

Top-down, as every pull: the outer fork's patch to `b/` first, then the
inner fork's patch. Since `vendor/a/b/` is selected too, its `fork` is
the inner fork, and it pulls from that one. It's fetched from both of
its upstreams, as when it isn't selected: the outer fork may move its
synced commit to one only the inner upstream has.

```scrut
$ git splice pull --upstream fork --all
ok   vendor/a fetched from fork
ok   vendor/a/b fetched from origin
ok   vendor/a/b fetched from fork
ok   vendor/a: pulled 1b1cea6
ok   vendor/a/b: pulled d5d5b62
```

```scrut
$ git splice status --upstream fork
On branch main

  ahead 3  vendor/a -> fork/main
  ahead 2  vendor/a/b -> fork/main
```

```scrut
$ git splice status
On branch main

  ahead 4  vendor/a -> origin/main
  ahead 3  vendor/a/b -> origin/main
```

### The default travels with the `.splice`

The push of `vendor/a/` publishes `vendor/a/b/.splice` with the rest of
its folder. Its `default-upstream` goes along, so in the outer upstream,
`b/` pulls and pushes by default where it does in the monorepo:

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed e824c9c to origin/main
```

```scrut
$ git -C "$UPSTREAM" show main:b/.splice
[splice]
	commit = d5d5b62373ad5b94d1393019ab51f2ad34bb43c2
	id = 548ac82ad47ea22d
	default-upstream = origin
[upstream "origin"]
	url = https://git.example.com/b.git
[upstream "fork"]
	url = https://git.example.com/company/b.git
```
