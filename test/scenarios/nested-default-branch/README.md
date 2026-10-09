# Scenario: nested-default-branch

A nested splice's `.splice` without `default-branch` means the same
branch in the monorepo as in the upstream it came from.

- **Monorepo**: empty, default branch `main`.
- **a's upstream (`$UPSTREAM`)**: default branch `master`. It uses git
  splice itself: b is spliced in at `b/`.
- **b's upstream (`$UPSTREAM-b.git`)**: default branch `master` too, so
  `b/.splice` doesn't name a default branch.

A `.splice` without `default-branch` means: the upstream's default
branch has the same name as the default branch of what the splice lives
in. In a's upstream, that's the repository, with `master`. In the
monorepo, it's a, which stands in for a's upstream there, and whose
default branch is `master` too. So b syncs with `master` in both places,
as it would in a separate clone of a's upstream. Before, a `.splice`
without `default-branch` followed the monorepo's default branch, `main`,
which b's upstream doesn't have
([#71](https://github.com/roschaefer/git-splice/issues/71)).

`clone` and `init` inside a splice follow the same rule: they record
`default-branch` only if the new upstream's default branch differs from
the one of the splice above. So the file means the same in both
directions.

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
ok   vendor/a: cloned ddf42f3 from master
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

So on the monorepo's `main`, both sync with `master`:

```scrut
$ git splice status
ok   vendor/a -> master (up to date)
ok   vendor/a/b -> master (up to date)
```

A change to b, pushed from `main`, goes to `master` in b's upstream,
which has no other branch:

```scrut
$ echo "b local" >>vendor/a/b/file.txt && git commit -q -a -m "b local" && git splice push vendor/a/b
ok   vendor/a/b: pushed 701ab17 to master
```

```scrut
$ git -C "$UPSTREAM-b.git" for-each-ref --format='%(refname:short)' refs/heads
master
```
