# Push before moving a splice

The workaround for [#4](https://github.com/roschaefer/git-splice/issues/4),
in the [same state](README.md): push the unpushed commit first, then move
the splice. The local commit then reaches the upstream with its own
message and author. The move changes no file inside the folder, so it
doesn't reach the upstream at all.

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

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed e859a6b to main
```

```scrut
$ git mv vendor/a libs/a && git -c user.name=Mover -c user.email=mover@example.com commit -q -m "reorganize folders"
```

A move changes no file inside the folder, so after a fetch under the new
path ([#21](https://github.com/roschaefer/git-splice/issues/21)), there is
nothing left to push:

```scrut
$ git splice fetch libs/a && git splice status
ok   libs/a fetched
ok   libs/a -> main (up to date)
```

```scrut
$ git -C "$UPSTREAM" log --format='%s  (%an)' main
local change  (Test)
seed  (Test)
```
