# Scenario: nested-default-branch

A nested splice's `.splice` without `default-revision` means the same
branch in the monorepo as in the upstream it came from.

- **Monorepo**: empty, default branch `main`.
- **Outer upstream (`$UPSTREAM`)**: default branch `master`. It uses
  `git-splice` itself: the inner upstream is spliced in at `b/`.
- **Inner upstream (`$UPSTREAM-b.git`)**: default branch `master` too,
  so `b/.splice` doesn't name a default branch.

A `.splice` without `default-revision` means: the upstream's default
branch has the same name as the default branch of what the splice lives
in. In the outer upstream, that's the repository, with `master`. In the
monorepo, it's `vendor/a/`, which stands in for the outer upstream
there, and whose default branch is `master` too. So `b/` syncs with
`master` in both places, as it would in a separate clone of the outer
upstream. Before, a `.splice` without `default-revision` followed the
monorepo's default branch, `main`, which the inner upstream doesn't have
([#71](https://github.com/roschaefer/git-splice/issues/71)).

`clone` and `init` inside a splice follow the same rule: they record
`default-revision` only if the new upstream's default branch differs from
the one of the splice above. So the file means the same in both
directions.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_nested_default_branch https://git.example.com/b.git
```

## In a plain clone of the outer upstream

As a separate folder with a clone of the outer upstream would have it,
`b/` syncs with `master`:

```scrut
$ git clone -q "$UPSTREAM" ../a-clone &&
>   git -C ../a-clone splice fetch
ok   b fetched
```

```scrut
$ git -C ../a-clone splice status
On branch master

  up to date  b
```

## In the monorepo

`clone` records the outer upstream's default branch, since it differs
from the monorepo's:

```scrut
$ git splice clone "$UPSTREAM" vendor/a
===  vendor/a: fetching $UPSTREAM
ok   vendor/a: cloned ddf42f3 from master
```

```scrut
$ git splice fetch
ok   vendor/a fetched
ok   vendor/a/b fetched
```

```scrut
$ git config --file vendor/a/.splice upstream.origin.default-revision
master
```

`vendor/a/b/.splice` came along unchanged, without one:

```scrut
$ git config --file vendor/a/b/.splice upstream.origin.default-revision
[1]
```

So on the monorepo's `main`, both sync with `master`:

```scrut
$ git splice status
On branch main

  up to date  vendor/a -> master
  up to date  vendor/a/b -> master
```

A change to `vendor/a/b/`, pushed from `main`, goes to `master` in the
inner upstream, which has no other branch:

```scrut
$ echo "b local" >>vendor/a/b/file.txt &&
>   git commit -q -a -m "b local" &&
>   git splice push vendor/a/b
ok   vendor/a/b: pushed 701ab17 to master
```

```scrut
$ git -C "$UPSTREAM-b.git" for-each-ref --format='%(refname:short)' refs/heads
master
```
