# Scenario: init-new-upstream

A folder that grew inside the monorepo, to be published to a new, empty
repository.

- **Monorepo (`lib/a`)**: two commits.
- **Upstream**: empty.

`init` only commits `.splice`. The first push starts the upstream at that
commit, with the folder as it is at `init`, followed by any commits after
it. Its history before that stays in the monorepo
([why](removed-before-init/README.md)).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_init_new_upstream
```

```scrut
$ git splice init lib/a "$UPSTREAM"
ok   lib/a: initialized -- 'git splice push lib/a' publishes it
```

```scrut
$ git splice status
??   lib/a -> main (upstream has no such branch; ahead 1 -- push would create it)
```

```scrut
$ git splice push lib/a
??   lib/a: upstream has no 'main' branch yet -- this push creates it
ok   lib/a: pushed 905f2b9 to main
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
splice: init lib/a
```
