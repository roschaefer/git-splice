# Scenario: nested-splices, a splice made around them

`git splice init vendor` makes the folder around `vendor/a/` a splice of
a new, empty upstream. From then on, `vendor/a/` lives in `vendor/`, so
a `.splice` of its without `default-branch` follows `vendor/`'s default
branch, not the monorepo's
([nested default branch](../02-nested-default-branch/README.md)).

The new upstream's default branch is `master`, the monorepo's `main`. So
`init` records, in `vendor/a/.splice`, the branch `vendor/a/` followed
before. `vendor/a/` keeps syncing with `main`, and `vendor/a/b/`, which
follows `vendor/a/`, does too. Without it, both would switch to `master`,
which their upstreams don't have. Only the splices directly inside need
it: the ones further down follow them.

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

Both sync with `main`, the monorepo's default branch:

```scrut
$ git splice status
On branch main

  up to date  vendor/a
  up to date  vendor/a/b
```

`vendor/` gets an empty upstream whose default branch is `master`:

```scrut
$ git init -q --bare -b master "$UPSTREAM-vendor.git" &&
>   git splice init vendor "$UPSTREAM-vendor.git"
ok   vendor: initialized -- 'git splice push vendor' publishes it
ok   vendor/a: records default-branch 'main' for origin, which it followed before
```

The `init` commit has `vendor/.splice` and the default branch
`vendor/a/` followed:

```scrut
$ git show --name-only --format=%s HEAD
splice: init vendor

vendor/.splice
vendor/a/.splice
```

```scrut
$ git config --file vendor/.splice upstream.origin.default-branch
master
```

```scrut
$ git config --file vendor/a/.splice upstream.origin.default-branch
main
```

So `vendor/` follows `master`, which its first push creates, and
`vendor/a/` and `vendor/a/b/` still sync with `main`:

```scrut
$ git splice status
On branch main

  new, ahead 1  vendor -> master  push creates the branch

  up to date    vendor/a
  up to date    vendor/a/b
```
