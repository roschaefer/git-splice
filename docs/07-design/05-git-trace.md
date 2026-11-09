# Checking what it runs

Git can list the commands `git-splice` runs. Capture them in a file to
inspect the actual repository operations without reading the implementation.

<!-- See `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../09-scenarios/readme-setup.sh" && source "$TESTDIR/git-trace-setup.bash" && build_scenario scenario_git_trace
```
-->

The folder `lib/` here is a splice with one commit to push
([setup](git-trace-setup.bash)). `GIT_TRACE` set to an absolute path makes Git add a line
to that file for each command:

```scrut
$ GIT_TRACE="$PWD/../trace" git splice status
On branch main

  ahead 1  lib
```

The trace includes discovery and config queries as well as writes.
Filter it to inspect the rebuild: `status` creates an upstream-shaped
commit to compare, but publishes no ref.

```scrut
$ sed -n 's/.*trace: built-in: //p' ../trace | grep '^git commit-tree '
git commit-tree --no-gpg-sign 5f5ab219661c5dba1f8904855aaa5867a97f2dc9 -p bde416459fbcc09c9b585f3b65a94cab3f68bfcd
```

## Use a file, not `GIT_TRACE=1`

`GIT_TRACE=1` traces to stderr, and `git-splice` silences stderr where a failure
is an expected answer, such as asking for a key that isn't set. Those commands
are missing from what you see, such as this one, which every command runs:

```scrut
$ GIT_TRACE=1 git splice status 2>&1 |
>     grep -c -- --show-toplevel
0
[1]
```

In the file, it's there:

```scrut
$ grep -c -- --show-toplevel ../trace
1
```

## What a push sends

A file also keeps the commands apart from the output. To see what a push writes,
start with an empty file and look for the commands that write. `commit-tree`
makes the rebuilt commit, `push` sends it, and `update-ref` records that the
upstream has it now:

```scrut
$ : >../trace &&
>   GIT_TRACE="$PWD/../trace" git splice push lib
ok   lib: pushed 0fd98a6 to main
```

```scrut
$ sed -n 's/.*trace: built-in: //p' ../trace |
>     grep -E '^git (commit-tree|push|update-ref) '
git commit-tree --no-gpg-sign 5f5ab219661c5dba1f8904855aaa5867a97f2dc9 -p bde416459fbcc09c9b585f3b65a94cab3f68bfcd
git push --quiet -- https://git.example.com/lib.git 0fd98a6c01e5ee8559e8c043c4593ed9d8dd6271:refs/heads/main
git update-ref --create-reflog refs/splices/lib/heads/main 0fd98a6c01e5ee8559e8c043c4593ed9d8dd6271
```

The list has more than `git-splice`'s own commands: Git adds the ones it runs
itself, here `pack-objects` for the push.

## What the trace doesn't show

Three things `git-splice` does without a `git` command:

- `init` and `clone --from-submodule` write `<path>/.splice` to the folder, then
  `git add` and `git commit` it, as you would. `clone --from-submodule` also
  removes the submodule's `.git` file and writes the edited `.gitmodules` the
  same way.
- While it records an upstream's key, a folder `.git/splice-keys.lock` keeps
  other `git-splice` commands from picking the same one.
- It writes temporary files outside the repository, for `git config --file` and
  a temporary `GIT_INDEX_FILE`.
