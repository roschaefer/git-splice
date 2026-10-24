# Scenario: clone-from-submodule, with a branch

The submodule names `branch = stable` in `.gitmodules`: the branch
`git submodule update --remote` follows. The splice follows it too:
`.splice` records it as the upstream's `default-branch`
([default-branch](../../../04-upstreams/01-default-branch/README.md)).

- **Monorepo, on `main`**: `vendor/a/` is a submodule of the upstream,
  checked out at `seed`, with `branch = stable`.
- **Upstream**: `seed`, then `newer` on `main`, and `stable fix` on
  `stable`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_submodule_with_branch
```

```scrut
$ git config --file .gitmodules --list
submodule.vendor/a.path=vendor/a
submodule.vendor/a.url=$UPSTREAM
submodule.vendor/a.branch=stable
```

```scrut
$ git splice clone --from-submodule vendor/a
===  vendor/a: fetching $UPSTREAM
ok   vendor/a: cloned bde4164 from the submodule
===  vendor/a: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a -- remove it once you don't need it (regex)
```

```scrut
$ git config --file vendor/a/.splice --get-regexp '^upstream\.'
upstream.origin.url $UPSTREAM
upstream.origin.default-branch stable
```

`main` syncs with `stable`, so `stable fix` is there to pull, and
`newer` isn't:

```scrut
$ git splice status
On branch main

  behind 1  vendor/a -> stable
```
