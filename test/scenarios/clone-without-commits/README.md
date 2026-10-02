# Scenario: init-without-commits

A brand-new monorepo, right after `git init`: the first thing to run into
when building a monorepo out of existing repositories.

- **Monorepo**: on `main`, which has no commits yet.
- **Remote**: one commit (`seed`) on `main`.
- **No remote is registered yet** -- `cmd_init` registers it itself.

`git subtree add` merges the remote's content into `HEAD` and checks the
working tree against it. Without a commit there is no `HEAD`, and
git-subtree fails with `ambiguous argument 'HEAD'` followed by `working
tree has modifications. Cannot add.` -- neither says what is wrong.

`git subtrees init vendor/a <upstream>` therefore checks for a commit
before it does anything, so it leaves no remote behind for a subtree it
couldn't add, and names the way out.

## Output

`scenario_init_without_commits` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_init_without_commits
```
-->

```scrut
$ git subtrees init vendor/a "$UPSTREAM"
!!   branch 'main' has no commits yet -- create one and re-run: git commit --allow-empty -m 'initial commit'
[1]
```

```scrut
$ git remote
```

After an initial commit, the same command adds the subtree:

```scrut
$ git commit -q --allow-empty -m 'initial commit' && git subtrees init vendor/a "$UPSTREAM"
===  vendor/a: registering remote -> $UPSTREAM
===  vendor/a: fetching
ok   vendor/a fetched
===  vendor/a: adding subtree from $UPSTREAM
git fetch vendor/a main
From $UPSTREAM
 * branch            main       -> FETCH_HEAD
Added dir 'vendor/a'
ok   vendor/a: added
```
