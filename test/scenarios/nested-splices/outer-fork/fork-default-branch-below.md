# A fork on another default branch, above

a's fork calls its default branch `trunk`, a's upstream `main`. b's
`.splice` records no default branch of its own: in a's repository, `b/`
follows a's. In the monorepo, it follows the default branch of the
upstream `vendor/a` uses. With two upstreams and no default, that's
`main` or `trunk`, and the monorepo's `main` would only be a guess
([#122](https://github.com/roschaefer/git-splice/issues/122)).

[`setup.bash`](setup.bash) builds the state of [outer-fork](README.md).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0="url.$UPSTREAM-b.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/b.git GIT_CONFIG_KEY_1="url.$UPSTREAM-fork.git.insteadOf" GIT_CONFIG_VALUE_1=https://git.example.com/company/a.git
```
-->

```scrut
$ build_scenario scenario_outer_fork https://git.example.com/b.git
```

```scrut
$ git -C "$UPSTREAM-fork.git" branch -m main trunk
```

`vendor/a/.splice` gets a's fork, on `trunk`, but no default upstream:

```scrut
$ git config --file vendor/a/.splice upstream.fork.url https://git.example.com/company/a.git && git config --file vendor/a/.splice upstream.fork.default-branch trunk && git commit -q -m "vendor/a: add the company fork" -- vendor/a/.splice
```

Commands on `vendor/a/b` refuse before they start, as those on
`vendor/a` do:

```scrut
$ git splice status vendor/a/b
!!   vendor/a/b follows the default branch of vendor/a, whose upstreams have different default branches (origin: main, fork: trunk), but no default -- commit one: git config --file vendor/a/.splice splice.default-upstream <name>
[1]
```

```scrut
$ git splice pull vendor/a/b
!!   vendor/a/b follows the default branch of vendor/a, whose upstreams have different default branches (origin: main, fork: trunk), but no default -- commit one: git config --file vendor/a/.splice splice.default-upstream <name>
[1]
```

With a's upstream as the default, `vendor/a/b` follows its `main`:

```scrut
$ git config --file vendor/a/.splice splice.default-upstream origin && git commit -q -m "vendor/a: a's upstream by default" -- vendor/a/.splice
```

```scrut
$ git splice status vendor/a/b
ok   vendor/a/b -> main (up to date)
```
