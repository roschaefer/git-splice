# Scenario: nested-default-branch

A nested splice's `.splice` without `default-branch` means another branch
in the monorepo than in the upstream it came from. This is a known bug,
[#71](https://github.com/roschaefer/git-splice/issues/71).

- **Monorepo**: empty, default branch `main`.
- **a's upstream (`$UPSTREAM`)**: default branch `master`. It uses git
  splice itself: b is spliced in at `b/`.
- **b's upstream (`$UPSTREAM-b.git`)**: default branch `master` too, so
  `b/.splice` doesn't name a default branch.

A `.splice` without `default-branch` means: the upstream's default
branch has the same name as the repository's. In a's upstream, that's
`master`, which is right. In the monorepo, it's `main`, which b's
upstream doesn't have. The file didn't change on the way, the repository
around it did.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_nested_default_branch https://git.example.com/b.git
```

## In a plain clone of a's upstream

As a separate folder with a clone of a's upstream would have it, b syncs
with `master`:

```scrut
$ git clone -q "$UPSTREAM" ../a-clone && git -C ../a-clone splice fetch && git -C ../a-clone splice status
ok   b fetched
ok   b -> master (up to date)
```

## In the monorepo

`clone` records a's default branch, since it differs from the
monorepo's:

```scrut
$ git splice clone "$UPSTREAM" vendor/a && git splice fetch
===  vendor/a: fetching $UPSTREAM
ok   vendor/a: cloned 5def392 from master
ok   vendor/a fetched
ok   vendor/a/b fetched
```

```scrut
$ git config --file vendor/a/.splice splice.default-branch
master
```

b's `.splice` came along unchanged, without one:

```scrut
$ git config --file vendor/a/b/.splice splice.default-branch
[1]
```

So on the monorepo's `main`, a syncs with `master`, but b with `main`,
which b's upstream doesn't have:

```scrut
$ git splice status
ok   vendor/a -> master (up to date)
??   vendor/a/b -> main (upstream has no such branch -- push would create it)
```

A change to b, pushed from `main`, creates a `main` branch in b's
upstream, next to `master`:

```scrut
$ echo "b local" >>vendor/a/b/file.txt && git commit -q -a -m "b local" && git splice push vendor/a/b
??   vendor/a/b: upstream has no 'main' branch yet -- this push creates it
ok   vendor/a/b: pushed 701ab17 to main
```

```scrut
$ git -C "$UPSTREAM-b.git" for-each-ref --format='%(refname:short)' refs/heads
main
master
```
