# Scenario: clone-from-submodule, with `branch = .`

The submodule names `branch = .` in `.gitmodules`: it follows the
upstream branch named like the monorepo's current one. A splice does
that already, so `.splice` records neither `default-branch` nor
`default-pin`.

- **Monorepo, on `main`**: `vendor/a/` is a submodule of the upstream,
  checked out at `seed`, with `branch = .`.
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
$ build_scenario scenario_submodule_with_branch_dot https://git.example.com/a.git
```

```scrut
$ cat .gitmodules
[submodule "vendor/a"]
	path = vendor/a
	url = https://git.example.com/a.git
	branch = .
```

```scrut
$ git splice clone --from-submodule vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned bde4164 from the submodule
===  vendor/a: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a -- remove it once you don't need it (regex)
```

```scrut
$ cat vendor/a/.splice
[splice]
	id = 680c4d19f10b5b95
	commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
[upstream "origin"]
	url = https://git.example.com/a.git
```

`main` syncs with the upstream's `main`, so `newer` is there to pull:

```scrut
$ git splice status
On branch main

  behind 1  vendor/a
```
