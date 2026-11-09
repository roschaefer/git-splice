# Checking what it runs

You can trust `git-splice` without reading its code. Everything it does to a
repository, it does by running the `git` command line, and Git can list those
commands for you.

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

This lists all of them for that one `status`, as you could type them.
`commit-tree` here computes the rebuild to compare with upstream, and writes no
ref:

```scrut
$ sed -n 's/.*trace: built-in: //p' ../trace
git version
git rev-parse --show-toplevel
git rev-parse --quiet --verify 'HEAD^{commit}'
git hash-object -t tree --stdin
git diff-tree -r --name-only -z 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD -- ':(top,glob)**/.splice'
git check-ref-format refs/splices/lib/branch
git config --blob HEAD:lib/.splice --list -z
git config --local -z --get-regexp '^splice\..*\.url$'
git check-ref-format refs/splices/lib/heads/main
git symbolic-ref --quiet --short HEAD
git config --local --get-all branch.main.splice
git symbolic-ref --quiet --short refs/remotes/origin/HEAD
git config --get init.defaultBranch
git config --blob HEAD:lib/.splice --get upstream.origin.default-pin
git config --blob HEAD:lib/.splice --get upstream.origin.default-branch
git status --porcelain -z --no-renames --untracked-files=normal -- ':(top,literal)lib'
git config --blob HEAD:lib/.splice --get upstream.origin.default-pin
git config --blob HEAD:lib/.splice --get upstream.origin.default-branch
git config --blob HEAD:lib/.splice --get splice.commit
git for-each-ref --count=1 refs/splices/lib/heads/
git show-ref --verify --quiet refs/splices/lib/heads/main
git rev-parse --verify --quiet HEAD:lib
git cat-file -t f51c3c7fe316a0dfa76abc5dd3e5a37ad1398f0d
git ls-tree -z f51c3c7fe316a0dfa76abc5dd3e5a37ad1398f0d
git mktree -z
git rev-parse 'refs/splices/lib/heads/main^{tree}'
git cat-file -e 'bde416459fbcc09c9b585f3b65a94cab3f68bfcd^{commit}'
git merge-base --is-ancestor bde416459fbcc09c9b585f3b65a94cab3f68bfcd refs/splices/lib/heads/main
git log --first-parent -1 --no-show-signature '--format=%H' HEAD -- ':(top,literal)lib/.splice'
git config --blob 5c3c4b4c1ec3c4915436f727f9c0f2e6bcb24a71:lib/.splice --get splice.id
git config --blob 5c3c4b4c1ec3c4915436f727f9c0f2e6bcb24a71^1:lib/.splice --get splice.id
git rev-parse --verify --quiet 5c3c4b4c1ec3c4915436f727f9c0f2e6bcb24a71^1
git diff-tree -r -z --no-renames --name-only --diff-filter=DM 5c3c4b4c1ec3c4915436f727f9c0f2e6bcb24a71^1 5c3c4b4c1ec3c4915436f727f9c0f2e6bcb24a71 -- ':(top,glob)**/.splice'
git config --blob 5c3c4b4c1ec3c4915436f727f9c0f2e6bcb24a71:lib/.splice --get splice.commit
git rev-parse --git-path shallow
git cat-file -e 'bde416459fbcc09c9b585f3b65a94cab3f68bfcd^{commit}'
git rev-parse 'bde416459fbcc09c9b585f3b65a94cab3f68bfcd^{tree}'
git rev-parse --verify --quiet 5c3c4b4c1ec3c4915436f727f9c0f2e6bcb24a71:lib
git cat-file -t 7c856c1dc33b046ce6074d056dfa611c71dc1549
git ls-tree -z 7c856c1dc33b046ce6074d056dfa611c71dc1549
git mktree -z
git rev-parse 'bde416459fbcc09c9b585f3b65a94cab3f68bfcd^{tree}'
git log --reverse --first-parent --no-show-signature '--pretty=tformat:%H%x00%an%x00%ae%x00%aD%x00%cn%x00%ce%x00%cD%x00%B%x00' 5c3c4b4c1ec3c4915436f727f9c0f2e6bcb24a71..HEAD -- ':(top,literal)lib'
git cat-file '--batch-check=%(objectname) %(objecttype)'
git commit-tree --no-gpg-sign 5f5ab219661c5dba1f8904855aaa5867a97f2dc9 -p bde416459fbcc09c9b585f3b65a94cab3f68bfcd
git rev-parse --verify --quiet 'refs/splices/lib/heads/main^{commit}'
git merge-base --is-ancestor bde416459fbcc09c9b585f3b65a94cab3f68bfcd 0fd98a6c01e5ee8559e8c043c4593ed9d8dd6271
git rev-list --left-right --count 0fd98a6c01e5ee8559e8c043c4593ed9d8dd6271...refs/splices/lib/heads/main
git config --get-colorbool color.status false
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
