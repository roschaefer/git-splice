# The `.splice` file

A folder is a splice because it has a committed `.splice` file. The file
names the upstream and the upstream commit the folder last matched: the
synced commit U(H) of the [sync model](../sync-model/README.md).

- The folder carries that state, so clones and branches have it and
  `git mv` moves it ([why](../../../docs/design/README.md#principles)).
- `pull` updates the synced commit. `push` publishes the folder without
  its own `.splice`, because the file describes the relationship from
  the monorepo side
  ([why](../../../docs/design/README.md#splicing-out-push-and-the-rebuild)).
- Upstreams use private refs instead of Git remotes, so a plain `git push`
  cannot publish the monorepo to one by mistake
  ([why](../../../docs/design/accidental-monorepo-push.md)).

```text
[splice]
	id = 9b2e41c07d5a8f36       # which splice this is, wherever it moves
	commit = 9bb866a3ba726f2229597a45e8ea3368f7e669a8 # the synced commit U(H)
[upstream "origin"]
	url = git@github.com:x/a.git
	default-branch = master
```

The file uses Git's config format, so `git config --file` reads and writes
it. Only the `.splice` committed in `HEAD` counts. Here,
`default-branch = master` maps the monorepo's default branch, say `main`,
to upstream `master`
([example](../../scenarios/04-upstreams/01-default-branch/README.md)).

To pin the monorepo's default branch at a tag or complete commit ID, use
`default-pin` in place of `default-branch`:

```text
[upstream "origin"]
	url = git@github.com:x/a.git
	default-pin = v1.2.3
```

`pull` then stays at that revision until `.splice` names another one, and
`push` refuses from the monorepo's default branch. Feature branches still
follow upstream branches of the same name
([example](../../scenarios/04-upstreams/06-default-pin/README.md)).
