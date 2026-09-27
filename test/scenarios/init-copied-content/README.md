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

Expected result: `init` reports that it recorded the last sync, the
worktree and `HEAD`'s tree are unchanged, the squash commit's
`git-subtree-split:` trailer names the remote's `main`, and a `push` from a
feature branch creates a remote branch descending from `main`.

Built by `scenario_init_copied_content` in `setup.bash`.
