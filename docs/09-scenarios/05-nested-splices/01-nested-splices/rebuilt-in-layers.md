# Scenario: nested-splices, rebuilt layer by layer

Each level can run the command for one level, in the repository its
splice is spliced into: the rebuild of the splice above. That gives the
monorepo's answer only if the rebuild of the splice above has all the
history the levels below need.

Here the monorepo pushes a change to `vendor/a/b/`, and then makes
`vendor/` a splice around `vendor/a/`. A splice's history starts where
it was made, so `vendor/`'s rebuild starts at its `init`, with the
pushed change folded into that one commit. The records carry it,
though: the rebuild of `vendor/` records `a/` at the rebuild of
`vendor/a/`, which has the pushed change as a commit of its own, and
that one records `b/` the same way. So rebuilt level by level, each
level comes out as the monorepo's own rebuild, commit for commit.
Before the rebuild wrote the records this way, `b/` had the change only
as part of the `init`, and diverged from its upstream
([#337](https://github.com/roschaefer/git-splice/pull/337)).

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

The monorepo pushes a change to `vendor/a/b/`:

```scrut
$ echo "b local" >>vendor/a/b/file.txt &&
>   git commit -q -a -m "b local" &&
>   git splice push vendor/a/b
ok   vendor/a/b: pushed 701ab17 to main
```

Then it makes `vendor/` a splice of a new upstream, around `vendor/a/`,
and changes `vendor/a/b/` again:

```scrut
$ git init -q --bare -b main "$UPSTREAM-vendor.git" &&
>   git splice init vendor "$UPSTREAM-vendor.git"
ok   vendor: initialized -- 'git splice push vendor' publishes it
```

```scrut
$ echo "b next" >>vendor/a/b/file.txt &&
>   git commit -q -a -m "b next"
```

## In the monorepo

The monorepo has *c* (`b local`), pushed to the inner upstream as *c'*,
then *i* (`splice: init vendor`) and *n* (`b next`). Each lane's R walks
them: `vendor/`'s starts at *i*, and in `vendor/a/b/`, R puts *n'* on the
pushed *c'*:

<div align="center">

![The monorepo's a, c, i and n, H at n; in the lane vendor/, with no upstream commits, dashed, i prime and n prime, R; in vendor/a/, drawn inside it, a's upstream commits k and l, T and U(H) at l, and dashed on l, c prime and n prime, R; in vendor/a/b/, drawn inside that, b's upstream commits m, U(H) and U(l), and c prime, T, and dashed on c prime, n prime, R](layers-in-the-monorepo.drawio.svg)

</div>

<!--
```scrut
$ check_drawing "$TESTDIR/layers-in-the-monorepo.drawio.svg" \
>   a=HEAD~3 c=HEAD~2 i=HEAD~1 n=HEAD k=refs/splices/upstream/heads/main~1 \
>   l=refs/splices/upstream/heads/main m=refs/splices/b/heads/main~1
ok   layers-in-the-monorepo.drawio.svg: 13 commits, 16 arrows, 7 boxes, 3 lanes
```
-->

The rebuild of `vendor/a/b/` has the pushed change, and `b next` on top:

```scrut
$ git log --format=%s "$(git splice rebuild vendor/a/b)"
b next
b local
b seed
```

```scrut
$ git splice status vendor/a/b
On branch main

  ahead 1  vendor/a/b
```

## Layer by layer

The rebuild of `vendor/`, checked out as the repository `vendor/` is
spliced from. Its history starts at the `init`:

```scrut
$ git worktree add -q -b layer/vendor ../vendor-layer "$(git splice rebuild vendor)"
```

The next commands run in that worktree:

```scrut
$ cd ../vendor-layer
```

```scrut
$ git log --format=%s
b next
splice: init vendor
```

In there, `a/` is a splice like any other. Its rebuild, checked out the
same way:

```scrut
$ git worktree add -q -b layer/a ../a-layer "$(git splice rebuild a)"
```

The next commands run in that worktree:

```scrut
$ cd ../a-layer
```

```scrut
$ git log --format=%s
b next
b local
add b
a seed
```

And in there, `b/`. Its rebuild has the pushed change as a commit of its
own, `b local`:

```scrut
$ git branch layer/b "$(git splice rebuild b)"
```

```scrut
$ git log --format=%s layer/b
b next
b local
b seed
```

Only `b next` is new, as in the monorepo:

```scrut
$ git splice log b
===  b (upstream has no 'layer/a' branch -- compared with 'main')
< b3c7929 b next  (Test <test@example.com>)
```

Each layer's branch is the same commit as the monorepo's rebuild of
that splice:

```scrut
$ git rev-parse --short=7 layer/a && git rev-parse --short=7 layer/b
0be5270
b3c7929
```

```scrut
$ (cd ../monorepo && git splice rebuild vendor/a | cut -c1-7 && git splice rebuild vendor/a/b | cut -c1-7)
0be5270
b3c7929
```
