# Scenario: clone-from-submodule, without a branch

The submodule names no `branch` in `.gitmodules`, as in the
[parent scenario](../README.md): it stays at its commit until someone
moves it. The splice stays too: `default-pin` pins that commit
([default-pin](../../../04-upstreams/06-default-pin/README.md)).

- **Monorepo, on `main`**: `vendor/a/` is a submodule of the upstream,
  checked out at `seed`.
- **Upstream**: `seed`, then `newer` on `main`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_submodule_without_branch
```

```scrut
$ git splice clone --from-submodule vendor/a
===  vendor/a: fetching $UPSTREAM
ok   vendor/a: cloned bde4164 from the submodule
===  vendor/a: pinned at bde4164, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/a/.splice --unset upstream.origin.default-pin
===  vendor/a: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a -- remove it once you don't need it (regex)
```

```scrut
$ git config --file vendor/a/.splice --get-regexp '^upstream\.'
upstream.origin.url $UPSTREAM
upstream.origin.default-pin bde416459fbcc09c9b585f3b65a94cab3f68bfcd
```

The upstream's `newer` doesn't count: `main` syncs with the pinned
commit, which the splice matches.

```scrut
$ git splice status
On branch main

  up to date  vendor/a -> bde4164
```

To follow `main` instead, remove the pin and commit that:

```scrut
$ git config --file vendor/a/.splice --unset upstream.origin.default-pin &&
>   git commit -q -m "vendor/a: follow main" vendor/a/.splice
```

Now `newer` is there to pull:

```scrut
$ git splice status
On branch main

  behind 1  vendor/a
```
