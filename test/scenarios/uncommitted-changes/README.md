# Scenario: uncommitted-changes

The splice's folder has a committed change and an uncommitted one. Like
every command, `push` reads the splice from the last commit, so it sends
only the committed change.

- **Monorepo (`vendor/a`)**: cloned at `seed`, then a local commit, then
  an edit to `file.txt` that isn't committed.
- **Upstream**: `seed`, unchanged.

## Output

`scenario_uncommitted_changes` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_uncommitted_changes
```
-->

`status` shows the committed change, and warns about the uncommitted one:

```scrut
$ git splice status
ok   vendor/a -> main (push: ahead 1)
??   vendor/a has uncommitted changes -- push only sends committed ones
```

`push` warns too, and sends what is committed:

```scrut
$ git splice push vendor/a
??   vendor/a: uncommitted changes aren't pushed -- commit them first
ok   vendor/a: pushed f5f3418 to main
```

The upstream now matches the last commit, but the edit is still only in
the folder:

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
??   vendor/a has uncommitted changes -- push only sends committed ones
```

Committing it makes it pushable:

```scrut
$ git commit -q -am "uncommitted change" && git splice push vendor/a
ok   vendor/a: pushed 7007d1c to main
```

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```
