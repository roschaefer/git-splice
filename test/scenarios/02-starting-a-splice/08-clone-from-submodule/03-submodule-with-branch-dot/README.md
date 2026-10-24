# Scenario: clone-from-submodule, with `branch = .`

The submodule names `branch = .` in `.gitmodules`: it follows the
upstream branch named like the monorepo's current one. A splice does
that already, so `.splice` records neither `default-branch` nor
`default-pin`.

- **Monorepo, on `main`**: `vendor/a/` is a submodule of the upstream,
  checked out at `seed`, with `branch = .`.
- **Upstream**: `seed`, then `newer` on `main`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_submodule_with_branch_dot
```

```scrut
$ git config --file .gitmodules --list
submodule.vendor/a.path=vendor/a
submodule.vendor/a.url=$UPSTREAM
submodule.vendor/a.branch=.
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
```

`main` syncs with the upstream's `main`, so `newer` is there to pull:

```scrut
$ git splice status
On branch main

  behind 1  vendor/a
```
