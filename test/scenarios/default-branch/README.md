# Scenario: default-branch

Upstream's default branch is `master`, the monorepo's is `main`.

- **Monorepo (`vendor/a`)**: cloned on `main`, then a local commit.
- **Upstream**: `seed` on `master`.

`clone` recorded `default-branch = master` in `.splice`, so on the
monorepo's default branch the splice syncs with `master`. Every other
branch keeps its name.

## Output

`scenario_default_branch` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_default_branch
```
-->

```scrut
$ git config --file vendor/a/.splice --list
splice.url=$UPSTREAM
splice.commit=bde416459fbcc09c9b585f3b65a94cab3f68bfcd
splice.default-branch=master
```

```scrut
$ git splice status
ok   vendor/a -> master (push)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed e859a6b to master
```
