# Scenario: never-fetched

A splice whose upstream hasn't been fetched in this clone yet, as right
after cloning the monorepo: the commits are there, the private refs with
upstream's branches aren't.

- **Monorepo (`vendor/a`)**: cloned at `seed`.
- **Upstream**: `seed`, never fetched here.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_never_fetched
```

```scrut
$ git splice status
??   vendor/a -> main (never fetched -- run 'git splice fetch vendor/a')
```

```scrut
$ git splice fetch
ok   vendor/a fetched
```

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```
