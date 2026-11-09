# --rebuilt-commit

`merge` and `push` accept a commit made outside the normal splice workflow.
They use it in different directions:

| Command | What the supplied commit does |
|---|---|
| `merge --rebuilt-commit <commit> <path>` | Brings content changes made on top of a rebuild back into the monorepo. |
| `push --rebuilt-commit <commit> <path>` | Publishes edited history whose final files match the committed splice content. |

## Bring back content changes

Create a worktree of `git splice rebuild <path>`, work on the splice as its
own repository, then merge the resulting commit back. This is a three-way
content merge, preserving monorepo changes made since the worktree branched.
It keeps the recorded upstream sync point: the supplied work is local work.

Like a squash merge, it takes changes rather than preserving the supplied
commit's identity. Rebase further work onto the new rebuild before merging
again. Upstream commits the monorepo has not taken in through pull are refused
when the tool can identify them in fetched upstream history.

Read the [merge option's exact rules](../04-merge.md#--rebuilt-commit), the
[worktree scenario](../../09-scenarios/01-everyday-sync/02-up-to-date/worked-on-in-a-worktree.md),
and the [upstream-pull refusal](../../09-scenarios/01-everyday-sync/02-up-to-date/upstream-pulled-in-a-worktree.md).

## Publish edited history

Reword or otherwise edit the rebuilt history before publication, retaining
the same final files. Push validates that the supplied tree matches the
committed splice content and, unless forced, contains its synced history.
It also checks that a subsequent pull can record the supplied history.
This takes one named splice, without `--all`.

Publication does not change the monorepo's sync point. Follow the push's
`pull --bump` reminder to record edited history before making more local changes.
See the [push option](../07-push.md#--rebuilt-commit) for all checks and its
command-line example.

A [push handler](01-exec/README.md) can return the same input through
[`result.rebuilt_commit`](01-exec/01-json-payload.md#result) at `after-rebuild`.
The [edited-history scenario](../../09-scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/edit-with-exec.md)
executes that path: pause, return an edited commit, continue publication, and
record it with `pull --bump`.
