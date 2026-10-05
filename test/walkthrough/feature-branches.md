# Feature branches

Every splice syncs with the upstream branch named like your current
branch. This walkthrough starts a feature branch in the
[sandbox](README.md), changes one splice on it and pushes, and cleans up
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

To tell whether a splice changed on `feature`, git-splice compares it with
the branch `feature` was cut from: `--base`, else the monorepo's default
branch (`origin/HEAD`, else `init.defaultBranch`; the sandbox sets the
latter).

```scrut
$ git splice status
ok   vendor/pkg-a -> feature (upstream has no such branch; unchanged since 'main')
ok   vendor/pkg-b -> feature (upstream has no such branch; unchanged since 'main')
```

## Changing one splice

```scrut
$ echo "a new option" >>vendor/pkg-b/file.txt && git commit -qam "pkg-b: add an option"
```

```scrut
$ git splice status
ok   vendor/pkg-a -> feature (upstream has no such branch; unchanged since 'main')
ok   vendor/pkg-b -> feature (upstream has no such branch; ahead 1 since 'main' -- push would create it)
```

With no upstream branch to compare with, `diff` compares with `main`:

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

`push` creates `feature` on `pkg-b`'s upstream only. `pkg-a` didn't
change, so its upstream doesn't get an empty branch.

```scrut
$ git splice push --all
ok   vendor/pkg-a: nothing to push (upstream has no 'feature' branch; unchanged since 'main')
??   vendor/pkg-b: upstream has no 'feature' branch yet -- this push creates it (changed since 'main')
ok   vendor/pkg-b: pushed 5023101 to feature
```

```scrut
$ git splice status
ok   vendor/pkg-a -> feature (upstream has no such branch; unchanged since 'main')
ok   vendor/pkg-b -> feature (up to date)
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
$ git for-each-ref --format='%(refname)' refs/splices/git.example.com/pkg-b/-/
refs/splices/git.example.com/pkg-b/-/main
```

```scrut
$ git splice status
ok   vendor/pkg-a -> main (up to date)
ok   vendor/pkg-b -> main (up to date)
```
