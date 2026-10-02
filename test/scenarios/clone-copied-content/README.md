# Scenario: init-copied-content

A folder that will become a subtree was copied in by hand: its content is
exactly the remote's, but it was never added with `git subtree add`, so
there is no sync point (no `git-subtree-dir:` trailer) in the history.

- **Monorepo**: `vendor/a` holds a copy of the remote's `file.txt`,
  committed as an ordinary commit. The base branch is `main`, via
  `init.defaultBranch`.
- **Remote**: one commit (`seed`) on `main`.
- **No remote is registered yet** -- `cmd_init` registers it itself.

Equal content alone makes `classify_subtree` report `up-to-date`. Without
a sync point, though, a later `push` would split a history that shares
nothing with the remote's, and a branch it creates wouldn't build on the
remote's `main`.

`git subtrees init vendor/a <upstream>` therefore records the sync point
itself: the same two commits `git subtree add --squash` creates, except
that the merge keeps the monorepo's tree. git-subtree can't do this on
its own: `add` refuses an existing folder, and `merge --squash` refuses a
folder that was never added.

The merge also carries the `git-subtree-mainline:` and
`git-subtree-split:` trailers of a `split --rejoin` merge. Without them,
`git subtree split` would follow the merge's first parent into the
folder's history from before the adoption, and the first push would
publish it -- including files deleted since, such as a secret committed
by mistake. `init.bats` covers that case.

`init.bats` also checks that `HEAD`'s tree is unchanged, that the squash
commit's `git-subtree-split:` trailer names the remote's `main`, and that a
`push` from a feature branch creates a remote branch descending from `main`.

## Output

`scenario_init_copied_content` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_init_copied_content
```
-->

```scrut
$ git subtrees init vendor/a "$UPSTREAM"
===  vendor/a: registering remote -> $UPSTREAM
===  vendor/a: fetching
ok   vendor/a fetched
ok   vendor/a: content matches 'main' on the remote -- recorded it as the last sync
```

The worktree is unchanged, and the history gains the two commits:

```scrut
$ git status --short
```

```scrut
$ git log --oneline --graph
*   8a4a412 Merge commit '1b35566e1b5044c8fce97445616726d9f2a3cc2c' as 'vendor/a'
|\  
| * 1b35566 Squashed 'vendor/a/' content from commit bde4164
* e3f7e4b copy vendor/a by hand
* 4d732bc initial commit
```

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (up to date)
```
