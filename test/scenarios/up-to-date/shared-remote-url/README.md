# Scenario: shared-remote-url

Two splices with the same upstream URL. They act like two clones of one
repository: each has its own synced commit and its own private refs.

- **Monorepo**: `vendor/a` and `vendor/b`, both cloned at `seed`.
- **Upstream**: one repository, `seed`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_shared_remote_url
```

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
ok   vendor/b -> main (up to date)
```

```scrut
$ echo "only in b" >>vendor/b/file.txt && git commit -q -am "change b"
```

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
ok   vendor/b -> main (push: ahead 1)
```
