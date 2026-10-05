# Committed conflict markers

In the [same state](README.md), the conflict in `vendor/a/.splice` is
committed with its markers. git-splice reads `.splice` with `git config`,
which can't read past the first marker. So every command stops with Git's
message, before a half-read `.splice` could make the splice look
unrelated to its upstream and suggest `push --force`
([#37](https://github.com/roschaefer/git-splice/issues/37)).

## Output

`scenario_concurrent_pulls` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_concurrent_pulls
```
-->

The folder's files are resolved, `.splice` isn't:

```scrut
$ git merge origin/main >/dev/null; git checkout --ours -- vendor/a/file.txt && git add vendor/a && git commit -q --no-edit
```

`git config` can't read it:

```scrut
$ git config --blob HEAD:vendor/a/.splice --get splice.commit
error: bad config line 2 in blob HEAD:vendor/a/.splice
[1]
```

Neither can git-splice, so it stops:

```scrut
$ git splice status
!!   vendor/a/.splice can't be read (bad config line 2 in blob HEAD:vendor/a/.splice) -- fix it and commit it
[1]
```

```scrut
$ git splice merge vendor/a
!!   vendor/a/.splice can't be read (bad config line 2 in blob HEAD:vendor/a/.splice) -- fix it and commit it
[1]
```

The fix is a readable `.splice` with the newer sync point. Here, the merge's
first parent has it:

```scrut
$ git checkout HEAD~1^1 -- vendor/a/.splice && git commit -q -m "fix vendor/a/.splice" && git splice status
ok   vendor/a -> main (up to date)
```
