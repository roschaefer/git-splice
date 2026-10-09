# Scenario: removed-before-init

Why a splice's upstream history starts at `init`: everything the folder
held before stays in the monorepo, including what was removed again.

- **Monorepo (`lib/a`)**: two commits, then a commit that adds a password
  to `config.txt`, and one that removes it again.
- **Upstream**: empty.

Until `init`, the folder was written for the monorepo, not for an
upstream. Its history may hold passwords, internal names or files that
were removed before anyone decided to publish the folder. So the first
push sends the folder as it is at `init`, as one commit: the init commit,
with its message and author. Every commit after it is pushed as usual.

The same goes for a folder that becomes a splice with `clone --merge`:
the upstream gets the merge, not the folder's history from before it.
It's the same concern as
[pushing the monorepo to a subfolder's upstream](../../../../docs/design/accidental-monorepo-push.md),
on a smaller scale: history reaching an upstream it wasn't meant for.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_removed_before_init
```

The password is in the monorepo's history:

```scrut
$ git log --format=%s -- lib/a
remove the password again
password = hunter2
second version
first version
```

```scrut
$ git splice init lib/a "$UPSTREAM" && git splice push lib/a
ok   lib/a: initialized -- 'git splice push lib/a' publishes it
??   lib/a: upstream has no 'main' branch yet -- this push creates it
ok   lib/a: pushed 905f2b9 to main
```

The upstream starts at the init commit:

```scrut
$ git -C "$UPSTREAM" log --format=%s main
splice: init lib/a
```

It never had `config.txt`, so it never had the password:

```scrut
$ git -C "$UPSTREAM" log --format=%s main -- config.txt
```
