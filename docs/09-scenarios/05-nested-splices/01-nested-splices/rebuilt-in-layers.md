# Scenario: nested-splices, rebuilt layer by layer

Each splice has a repository it's spliced into, and `git-splice` works the
same in any of them. So the commands for one level could run once per
level: rebuild the outer splice, check that out as its repository, and
run the command for the inner splice there. This page tries that with
today's commands, in worktrees, and compares it with what the monorepo
says.

It works as long as each level's history has everything the levels below
it need. Here it doesn't: `vendor/` is made a splice around `vendor/a/`
after the monorepo pushed a change to `vendor/a/b/`. A splice's history
starts where it was made, so `vendor/`'s history starts at its `init`,
with everything before folded into that one commit, the pushed change
too. Rebuilt from there, `b/` has the pushed change in the wrong commit,
and diverges from its upstream. The monorepo's own rebuild walks its
commits for `vendor/a/b/`, and has it.

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

The monorepo has c (`b local`), pushed to the inner upstream as c', then
i (`splice: init vendor`) and n (`b next`). Each lane's R walks them:
`vendor/`'s starts at i, and in `vendor/a/b/`, R puts n' on the pushed
c':

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
splice: init vendor
add b
a seed
```

And in there, `b/`. Its rebuild has the pushed change only as part of
`splice: init vendor`:

```scrut
$ git branch layer/b "$(git splice rebuild b)"
```

```scrut
$ git log --format=%s layer/b
b next
splice: init vendor
b seed
```

So `log` marks the pushed `b local` and `splice: init vendor` with `=`,
the same change on both sides: `b/` has diverged from its upstream.

```scrut
$ git splice log b
===  b (upstream has no 'layer/a' branch -- compared with 'main')
< 9c61af7 b next  (Test <test@example.com>)
= 701ab17 b local  (Test <test@example.com>)
= e23fdcf splice: init vendor  (Test <test@example.com>)
```

Each layer's branch rebuilds the one above it, so its commits are copies
of copies: i'' and n'' of i' and n', and i''' and n''' of those. In
`vendor/a/b/`, `layer/b` puts i''' on m, next to the upstream's c', the
same change in two commits:

<div align="center">

![The monorepo's a, c, i and n, H at n; in the lane vendor/, dashed, i prime and n prime, layer/vendor; in vendor/a/, drawn inside it, a's upstream commits k and l, T and U(H) at l, and dashed on l, i double prime and n double prime, layer/a; in vendor/a/b/, drawn inside that, b's upstream commits m, U(H) and U(l), and c prime, T, and dashed on m, i triple prime and n triple prime, layer/b](layers-one-by-one.drawio.svg)

</div>

<!--
```scrut
$ (cd ../monorepo && check_drawing "$TESTDIR/layers-one-by-one.drawio.svg" \
>   a=HEAD~3 c=HEAD~2 i=HEAD~1 n=HEAD k=refs/splices/upstream/heads/main~1 \
>   l=refs/splices/upstream/heads/main m=refs/splices/b/heads/main~1 \
>   "i''=layer/a~1" "n''=layer/a" "i'''=layer/b~1" "n'''=layer/b")
ok   layers-one-by-one.drawio.svg: 14 commits, 17 arrows, 7 boxes, 3 lanes
```
-->
