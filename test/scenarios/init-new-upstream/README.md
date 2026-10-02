# Scenario: init-new-upstream

A folder that grew inside the monorepo, to be published to a new, empty
repository.

- **Monorepo (`lib/a`)**: two commits.
- **Upstream**: empty.

`init` only commits `.splice`. The first push sends the folder's whole
history, rebuilt as if it had always been its own repository.

## Output

`scenario_init_new_upstream` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_init_new_upstream
```
-->

```scrut
$ git splice init lib/a "$UPSTREAM"
ok   lib/a: initialized -- 'git splice push lib/a' publishes it
```

```scrut
$ git splice status
??   lib/a -> main (no such branch upstream -- push would create it)
```

```scrut
$ git splice push lib/a
??   lib/a: upstream has no 'main' branch yet -- this push creates it
ok   lib/a: pushed ef82a18 to main
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
second version
first version
```
