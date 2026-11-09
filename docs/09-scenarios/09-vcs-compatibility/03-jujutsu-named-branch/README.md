# Scenario: Jujutsu and a named Git branch

A colocated jj repository shares Git's storage and working copy. A
submodule's contents are not managed by jj; a splice's ordinary files are.
Syncing still needs a named Git branch, which jj does not keep selected.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds a plain monorepo and a second one with
`vendor/lib/` spliced in:

```scrut
$ build_scenario scenario_jujutsu_named_branch
```

```scrut
$ jj --version
jj 0.46.0-7d382314f9420b4b8d932245b49c99492c812b9f
```

jj ignores changes inside a submodule:

```scrut
$ git submodule add -q https://git.example.com/lib.git vendor/lib &&
>   git commit -q -m "add submodule" &&
>   jj git init --colocate
Done importing changes from the underlying Git repo.
ignoring git submodule at "vendor/lib"
Initialized repo in "."
[0]
```

```scrut
$ echo "fix" >>vendor/lib/src/parse.txt &&
>   echo "use fix" >>app/main.txt &&
>   jj diff --stat
app/main.txt | 1 +
1 file changed, 1 insertion(+), 0 deletions(-)
[0]
```

The commands now run in the monorepo with a splice:

```scrut
$ cd ../splice-monorepo
```

jj sees both the app and the library's files:

```scrut
$ jj git init --colocate
Done importing changes from the underlying Git repo.
Setting the revset alias `trunk()` to `main@origin`.
Hint: The following remote bookmarks aren't associated with the existing local bookmarks:
  main@origin
Hint: Run the following command to keep local bookmarks updated on future pulls:
  jj bookmark track main@origin
Initialized repo in "."
```

```scrut
$ echo "fix" >>vendor/lib/src/parse.txt &&
>   echo "use fix" >>app/main.txt &&
>   jj diff --stat
app/main.txt             | 1 +
vendor/lib/src/parse.txt | 1 +
2 files changed, 2 insertions(+), 0 deletions(-)
```

Committing with jj leaves Git without a selected branch:

```scrut
$ jj commit -m "fix parse and use it"
Working copy  (@) now at: qpvuntsm 3d5cafa0 (empty) (no description set)
Parent commit (@-)      : sqpuoqvx 5ddf1c30 fix parse and use it
```

```scrut
$ git splice push vendor/lib
!!   not on a branch (detached HEAD) -- git splice requires a named branch
[1]
```

Move the bookmark to the committed change, then select it with Git:

```scrut
$ jj bookmark set main -r @-
Moved 1 bookmarks to sqpuoqvx 5ddf1c30 main* | fix parse and use it
```

```scrut
$ git checkout -q main && git splice push vendor/lib
ok   vendor/lib: pushed 9a5ab8d to main
```

A later jj operation can detach Git's `HEAD` again. This is a workaround
for each sync, not native jj integration:

```scrut
$ jj new --quiet && git status | head -n 1
HEAD detached from refs/heads/main
```
