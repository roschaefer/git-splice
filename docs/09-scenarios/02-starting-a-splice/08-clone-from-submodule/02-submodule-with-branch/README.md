# Scenario: clone-from-submodule, with a branch

The submodule names `branch = stable` in `.gitmodules`: the branch
`git submodule update --remote` follows. The splice follows it too:
`.splice` records it as the upstream's `default-branch`
([default-branch](../../../04-upstreams/01-default-branch/README.md)).

- **Monorepo, on `main`**: `vendor/a/` is a submodule of the upstream,
  checked out at `seed`, with `branch = stable`.
- **Upstream** (`$UPSTREAM`, reached as `https://git.example.com/a.git`):
  `seed`, then `newer` on `main`, and `stable fix` on
  `stable`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh" && export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_submodule_with_branch https://git.example.com/a.git
```

```scrut
$ cat .gitmodules
[submodule "vendor/a"]
	path = vendor/a
	url = https://git.example.com/a.git
	branch = stable
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
	id = 9ec04ba433cffaa4
	commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
[upstream "origin"]
	url = https://git.example.com/a.git
	default-branch = stable
```

`main` syncs with `stable`, so `stable fix` is there to pull, and
`newer` isn't:

```scrut
$ git splice status
On branch main

  behind 1  vendor/a -> stable
```
