# Checking what it runs

You can trust `git-splice` without reading its code. Everything it does to a
repository, it does by running the `git` command line, and Git can list those
commands for you.

<!-- See `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../scenarios/readme-setup.sh" && build_scenario scenario_git_trace
```
-->

The folder `lib/` here is a splice with one commit to push
([setup](setup.bash)). `GIT_TRACE` set to an absolute path makes Git add a line
to that file for each command:

```scrut
$ GIT_TRACE="$PWD/../trace" git splice status
On branch main

  ahead 1  lib
```

This lists the first few, as you could type them:

```scrut
$ sed -n 's/.*trace: built-in: //p' ../trace |
>     head -n 3
git version
git rev-parse --show-toplevel
git rev-parse --quiet --verify 'HEAD^{commit}'
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
