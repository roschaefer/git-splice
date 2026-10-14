# Scenario: submodule-in-linked-worktree

A submodule, checked out in the monorepo and in a linked worktree of it.

- **Monorepo, on `main`**: `vendor/a/` is a submodule of the upstream,
  checked out.
- **Linked worktree `../feature/`, on `feature`**: the same submodule,
  initialized and checked out there too.
- **Upstream**: `seed`.

Converting the submodule on `main` removes its settings,
`submodule.<name>.*`, from `.git/config`. All worktrees share that file,
so the submodule in `../feature/` counts as uninitialized from then on.
Git itself advises against several worktrees of a monorepo with
submodules: "the support for submodules is incomplete", says the
[`git worktree` documentation](https://git-scm.com/docs/git-worktree#_bugs).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_submodule_in_linked_worktree
```

Before, the other worktree has the submodule initialized:

```scrut
$ git -C ../feature submodule status
 bde416459fbcc09c9b585f3b65a94cab3f68bfcd vendor/a (heads/main)
```

```scrut
$ git splice clone --from-submodule vendor/a
===  vendor/a: fetching $UPSTREAM
ok   vendor/a: cloned bde4164 from the submodule
===  vendor/a: the submodule's repository stays in .*/monorepo/\.git/modules/vendor/a -- remove it once you don't need it (regex)
```

After, the submodule's settings are gone, for every worktree:

```scrut
$ git config --get-regexp '^submodule\.' || echo "no submodule settings"
no submodule settings
```

```scrut
$ git -C ../feature submodule status
-bde416459fbcc09c9b585f3b65a94cab3f68bfcd vendor/a
```

`../feature/` still has the files, but `git submodule update` skips the
submodule until `git submodule update --init` sets it up again:

```scrut
$ ls ../feature/vendor/a
file.txt
```

```scrut
$ git -C ../feature submodule update && git -C ../feature submodule status
-bde416459fbcc09c9b585f3b65a94cab3f68bfcd vendor/a
```

Merging `main` into `feature` fails like in every checkout that has the
submodule's files, a colleague's clone too: from the merge's view they're
untracked files in the way.

```scrut
$ git -C ../feature merge -q main
error: The following untracked working tree files would be overwritten by merge:
	vendor/a/file.txt
Please move or remove them before you merge.
Aborting
[1]
```

`git submodule deinit -f` removes the checkout, also here, where the
submodule's settings are gone already. Then the merge converts the
submodule in `feature` too:

```scrut
$ git -C ../feature submodule deinit -q -f vendor/a && git -C ../feature merge -q main && git -C ../feature status --short && ls -A ../feature/vendor/a
.splice
file.txt
```
