# Scenario: init-on-feature-branch

You start using a remote on a feature branch, before the remote has that
branch.

- **Monorepo**: on `feature`, cut from `main`. No `vendor/a` yet. The base
  branch is `main`, via `init.defaultBranch`.
- **Remote**: only has `main`, at `seed`. No `feature` branch.

`git subtrees init vendor/a <upstream>` can't add `feature`, so it adds the
remote's `main` instead -- the branch named like the monorepo's base branch.
This matches `push`: the subtree now differs from the monorepo's `main`, so
the first `git subtrees push` creates `feature` on the remote, on top of its
`main`.

## Output

`scenario_init_on_feature_branch` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_init_on_feature_branch
```
-->

```scrut
$ git subtrees init vendor/a "$UPSTREAM"
===  vendor/a: registering remote -> $UPSTREAM
===  vendor/a: fetching
ok   vendor/a fetched
===  vendor/a: remote has no 'feature' branch yet -- using its 'main' branch; your first push creates 'feature'
===  vendor/a: adding subtree from $UPSTREAM
git fetch vendor/a main
From $UPSTREAM
 * branch            main       -> FETCH_HEAD
Added dir 'vendor/a'
ok   vendor/a: added
```

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (no 'feature' branch on remote; changed since 'main' -- push would create it)
 vendor/a/file.txt | 1 +
 1 file changed, 1 insertion(+)
```

```scrut
$ git subtrees push
??   vendor/a: remote has no 'feature' branch yet -- this push will create it (changed since 'main')
git push using:  vendor/a feature
To $UPSTREAM
 * [new branch]      bde416459fbcc09c9b585f3b65a94cab3f68bfcd -> feature
ok   vendor/a: pushed
```

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (up to date)
```
