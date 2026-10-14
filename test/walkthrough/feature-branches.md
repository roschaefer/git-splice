# Feature branches

Every splice syncs with the upstream branch named like your current
branch. This walkthrough starts a feature branch in the
[sandbox](../../docs/sandbox.md), changes one splice on it and pushes, and cleans up
once the feature is merged on both sides.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

First, splice in `pkg-b` and bring both splices up to date, as in the
[main walkthrough](README.md#pull):

```scrut
$ git splice clone https://git.example.com/pkg-b.git vendor/pkg-b >/dev/null && git splice pull --all >/dev/null
```

## A new branch

Neither upstream has a `feature` branch.

```scrut
$ git switch -c feature
Switched to a new branch 'feature'
```

For each splice, `status` counts the commits that a push creating `feature`
upstream would publish: those that no upstream branch has yet. Right after
switching there are none.

```scrut
$ git splice status
On branch feature

  unchanged, no upstream branch  vendor/pkg-a
  unchanged, no upstream branch  vendor/pkg-b
```

## Changing one splice

```scrut
$ echo "a new option" >>vendor/pkg-b/file.txt && git commit -qam "pkg-b: add an option"
```

```scrut
$ git splice status
On branch feature

  new, ahead 1                   vendor/pkg-b  push creates the branch

  unchanged, no upstream branch  vendor/pkg-a
```

Without an upstream branch there's no [T](../concepts/sync-model/README.md) to
compare R with, so `diff` starts from the last commit upstream has:

```scrut
$ git splice diff
===  vendor/pkg-b
diff --git a/file.txt b/file.txt
index b041961..b509b97 100644
--- a/file.txt
+++ b/file.txt
@@ -1 +1,2 @@
 pkg-b: seed
+a new option
```

`push` creates `feature` on `pkg-b`'s upstream only. `pkg-a`'s upstream
has every commit already, so it doesn't get an empty branch. Commits that
`feature` got from `main` would count too, if upstream lacked them: that's
how they get upstream when it takes changes only through PRs
([scenario](../scenarios/up-to-date/push-ahead/feature-branch-from-main/README.md)).

```scrut
$ git splice push --all
ok   vendor/pkg-a: nothing to push (upstream has no 'feature' branch, but has every commit)
??   vendor/pkg-b: upstream has no 'feature' branch yet -- this push creates it
ok   vendor/pkg-b: pushed 5023101 to feature
```

```scrut
$ git splice status
On branch feature

  up to date                     vendor/pkg-b
  unchanged, no upstream branch  vendor/pkg-a
```

`pull` on `feature` pulls from `pkg-b`'s `feature` branch. `pkg-a`'s
upstream has no `feature` branch, so there's nothing to pull from it:

```scrut
$ git splice pull --all
ok   vendor/pkg-a fetched
ok   vendor/pkg-b fetched
ok   vendor/pkg-a: upstream has no 'feature' branch -- nothing to pull
ok   vendor/pkg-b: nothing to pull
```

## After the merge

The feature gets merged on both sides: on `pkg-b`'s upstream, which then
deletes the branch, and in the monorepo.

```scrut
$ git -C "$WALKTHROUGH/upstream/pkg-b.git" push -q . feature:main && git -C "$WALKTHROUGH/upstream/pkg-b.git" branch -q -D feature
```

```scrut
$ git switch -q main && git merge -q --ff-only feature
```

Back on `main`, `pull` sees that the monorepo already has what upstream
merged. Fetching pruned the deleted branch.

```scrut
$ git splice pull --all
ok   vendor/pkg-a fetched
ok   vendor/pkg-b fetched (main moved 9b3cb02..5023101)
ok   vendor/pkg-a: nothing to pull
ok   vendor/pkg-b: nothing to pull
```

```scrut
$ git for-each-ref --format='%(refname)' refs/splices/pkg-b/
refs/splices/pkg-b/main
```

```scrut
$ git splice status
On branch main

  up to date  vendor/pkg-a
  up to date  vendor/pkg-b
```
