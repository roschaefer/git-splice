# The `.splice` file

A folder is a splice because it has a `.splice` file, committed like any
other file. It names the upstream, and the upstream commit the folder
last matched, the synced commit U(H) of the
[sync model](../sync-model/README.md). That's all the state there is: a
clone of the monorepo has every splice, with nothing to set up.

```text
[splice]
	id = 9b2e41c07d5a8f36       # which splice this is, wherever it moves
	commit = 9bb866a3ba726f2229597a45e8ea3368f7e669a8 # the synced commit U(H)
[upstream "origin"]
	url = git@github.com:x/a.git
	default-branch = master     # only if it's named differently, see below
```

- **It's in Git's config format**, so `git config --file` reads it. Only
  the `.splice` committed in `HEAD` counts.
- **`clone` and `init` create it; `merge` and `pull` update it.** `push`
  does not change the monorepo, so it does not change `.splice`.
- **`default-branch` names the branch to follow** when it differs from
  the monorepo branch. For example, it can map monorepo `main` to
  upstream `master`
  ([example](../../scenarios/04-upstreams/01-default-branch/README.md)).
- **`default-pin` follows a tag or commit instead of a branch.** `pull`
  stays at that revision until `.splice` names another one, and `push`
  refuses there ([example](../../scenarios/04-upstreams/06-default-pin/README.md)).

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../walkthrough/scrut-setup.sh"
```
-->

Upstreams are fetched into private refs, not configured as Git remotes. A
plain `git push` therefore cannot publish the whole monorepo to a splice's
upstream by mistake
([why that matters](../../../docs/design/accidental-monorepo-push.md)).

```scrut
$ git remote
```

`pull` records the new synced commit in `.splice` and commits it with the
folder. The folder carries its own state, so clones and branches have it,
and `git mv` moves it
([design principle](../../../docs/design/README.md#principles)).

```scrut
$ before="$(git config --file vendor/pkg-a/.splice splice.commit)" &&
>   git splice pull vendor/pkg-a >/dev/null &&
>   printf '%s -> %s\n' "$before" "$(git config --file vendor/pkg-a/.splice splice.commit)"
9bb866a3ba726f2229597a45e8ea3368f7e669a8 -> 703b9360f7ac335a1134e9b5771a90a7c09ba39a
```

`push` publishes the folder as the upstream repository, without the
splice's own `.splice`. That file describes the relationship from the
monorepo side; it is not part of the upstream's files
([how push rebuilds the folder](../../../docs/design/README.md#splicing-out-push-and-the-rebuild)).

```scrut
$ echo "a local fix" >>vendor/pkg-a/file.txt &&
>   git commit -qam "pkg-a: a local fix" &&
>   git splice push vendor/pkg-a >/dev/null &&
>   git ls-tree --name-only refs/splices/pkg-a/heads/main
file.txt
```
