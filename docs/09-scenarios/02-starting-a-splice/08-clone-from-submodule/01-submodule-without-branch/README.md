# Scenario: clone-from-submodule, without a branch

The submodule names no `branch` in `.gitmodules`, as in the
[parent scenario](../README.md): it stays at its commit until someone
moves it. The splice stays too: `default-pin` pins that commit
([default-pin](../../../04-upstreams/06-default-pin/README.md)).

- **Monorepo, on `main`**: `vendor/a/` is a submodule of the upstream,
  checked out at `seed`.
- **Upstream** (`$UPSTREAM`, reached as `https://git.example.com/a.git`):
  `seed`, then `newer` on `main`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_submodule_without_branch https://git.example.com/a.git
```

```scrut
$ git splice clone --from-submodule vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned bde4164 from the submodule
===  vendor/a: pinned at bde4164, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/a/.splice --unset upstream.origin.default-pin
===  vendor/a: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a -- remove it once you don't need it (regex)
```

```scrut
$ cat vendor/a/.splice
[splice]
	id = e4779bec163bd89d
	commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
[upstream "origin"]
	url = https://git.example.com/a.git
	default-pin = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
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
