# Scenario: default-branch

Upstream's default branch is `master`, the monorepo's is `main`.

- **Monorepo (`vendor/a/`)**: cloned on `main`, then a local commit.
- **Upstream** (`$UPSTREAM`, reached as `https://git.example.com/a.git`):
  `seed` on `master`.

`clone` recorded `default-branch = master` for the upstream in
`.splice`, so on the
monorepo's default branch the splice syncs with `master`. Every other
branch keeps its name.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$UPSTREAM.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/a.git
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_default_branch https://git.example.com/a.git
```

```scrut
$ cat vendor/a/.splice
[splice]
	id = 224f2c2563d3b6f7
	commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
[upstream "origin"]
	url = https://git.example.com/a.git
	default-branch = master
```

```scrut
$ git splice status
On branch main

  ahead 1  vendor/a -> master
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed e859a6b to master
```
