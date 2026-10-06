# Scenario: default-branch

Upstream's default branch is `master`, the monorepo's is `main`.

- **Monorepo (`vendor/a`)**: cloned on `main`, then a local commit.
- **Upstream**: `seed` on `master`.

`clone` recorded `default-branch = master` in `.splice`, so on the
monorepo's default branch the splice syncs with `master`. Every other
branch keeps its name.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_default_branch
```

```scrut
$ git config --file vendor/a/.splice --list
splice.commit=bde416459fbcc09c9b585f3b65a94cab3f68bfcd
splice.default-branch=master
upstream.origin.url=$UPSTREAM
```

```scrut
$ git splice status
ok   vendor/a -> master (push: ahead 1)
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed e859a6b to master
```
