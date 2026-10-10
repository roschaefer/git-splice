# Scenario: outer-fork

The splice above has a second upstream, the one below doesn't
([#107](https://github.com/roschaefer/git-splice/issues/107)). In the
names of [nesting](../../../concepts/nesting/README.md): O is a's
upstream, spliced in at `vendor/a/`, and I is b's, at `vendor/a/b/`.
O's company fork carries a patch to `b/`.

- **b's upstream** (I, reached as `https://git.example.com/b.git`):
  `b seed`.
- **a's upstream** (O, `$UPSTREAM`): `a seed`, then `add b`.
- **a's fork** (`$UPSTREAM-fork.git`, reached as
  `https://git.example.com/company/a.git`): a copy of a's upstream, then
  `a fork patch to b`, which changes `b/file.txt`.
- **b's fork** (`$UPSTREAM-b-fork.git`, reached as
  `https://git.example.com/company/b.git`): a copy of b's upstream, then
  `b fork patch`. Only [same-name-below](same-name-below.md) uses it.
- **Monorepo**: `vendor/a/` and `vendor/a/b/`, as in
  [nested-splices](../README.md).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1="url.$UPSTREAM-fork.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/company/a.git GIT_CONFIG_KEY_2="url.$UPSTREAM-b-fork.git.insteadOf" GIT_CONFIG_VALUE_2=https://git.example.com/company/b.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_outer_fork https://git.example.com/b.git
```

`vendor/a/.splice` gets a's fork as a second upstream, and keeps a's
upstream as its default:

```scrut
$ git config --file vendor/a/.splice upstream.fork.url https://git.example.com/company/a.git && git config --file vendor/a/.splice splice.default-upstream origin && git commit -q -m "vendor/a: add the company fork" -- vendor/a/.splice
```

```scrut
$ git splice status
ok   vendor/a -> origin/main (up to date)
ok   vendor/a/b -> main (up to date)
```

### `--upstream` applies to the splices named

`vendor/a/b/.splice` names no `fork`, so every splice can't pull from
one:

```scrut
$ git splice pull --upstream fork --all
!!   no upstream 'fork' in vendor/a/b -- name only the splices that have one: vendor/a
[1]
```

Only `vendor/a`, then. Its pull also fetches the splice below it, whose
synced commit the pull may move: from every upstream it names, since
which of them has the new one isn't known. For I, that's its only one:

```scrut
$ git splice pull --upstream fork vendor/a
ok   vendor/a fetched from fork
ok   vendor/a/b fetched
ok   vendor/a: pulled 697c854
```

The fork's patch to `b/` is in `vendor/a/b/` now. I's `.splice` didn't
change, so the patch is a local change to I: the next push sends it to
b's upstream, as if it had been made in the monorepo. For `vendor/a`,
it's a commit a's upstream lacks, like any other the fork has.

```scrut
$ git splice status
ok   vendor/a -> origin/main (push: ahead 1)
ok   vendor/a/b -> main (push: ahead 1)
```

```scrut
$ git splice log vendor/a/b
===  vendor/a/b (main)
< c163a9d a fork patch to b  (Test <test@example.com>)
```
