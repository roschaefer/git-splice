# Scenario: moved-with-unpushed-commits

A splice with an unpushed commit is moved with `git mv`. The next push
sends the unpushed commit with its own message and author. The move
changes no file inside the folder, so it doesn't reach the upstream at
all.

- **Monorepo (`vendor/a`)**: cloned at `seed`, then a local commit,
  `local change`, not pushed yet.
- **Upstream**: `seed`.

`push` rebuilds the commits that changed the splice's folder. It follows
the folder through the move, and rebuilds the commits from before it
under the old path.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_moved_with_unpushed_commits
```

Before the move, the local commit is waiting to be pushed:

```scrut
$ git splice log
===  vendor/a (main)
< e859a6b local change  (Test <test@example.com>)
```

Someone else reorganizes the folders:

```scrut
$ git mv vendor/a libs/a && git -c user.name=Mover -c user.email=mover@example.com commit -q -m "reorganize folders"
```

The local commit is still the one to push:

```scrut
$ git splice log
===  libs/a (main)
< e859a6b local change  (Test <test@example.com>)
```

```scrut
$ git splice push libs/a
ok   libs/a: pushed e859a6b to main
```

```scrut
$ git -C "$UPSTREAM" log --format='%s  (%an)' main
local change  (Test)
seed  (Test)
```

```scrut
$ git splice status
ok   libs/a -> main (up to date)
```
