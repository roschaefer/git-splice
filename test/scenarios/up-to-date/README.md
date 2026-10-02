# Scenario: up-to-date

A splice freshly cloned and never touched again on either side.

- **Monorepo (`vendor/a`)**: cloned at `seed`, no local changes since.
- **Upstream**: `seed`, unchanged.

## Output

`scenario_up_to_date` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_up_to_date
```
-->

Nothing to do on either side:

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```

```scrut
$ git splice push vendor/a
ok   vendor/a: nothing to push
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: nothing to pull
```
