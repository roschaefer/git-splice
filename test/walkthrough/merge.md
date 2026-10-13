# merge

`git splice merge [--upstream <name>] [--bump] (<path>… | --all)`

Splices in what was fetched, without contacting the upstream, as one
ordinary commit per splice. It works like `git merge --squash`, done
internally with a cherry-pick: on a conflict, `git status` shows a
cherry-pick in progress
([diverged history](diverged.md) resolves one).

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

In the [sandbox](sandbox.md), `vendor/pkg-a`'s upstream has a commit the
monorepo doesn't have yet, and it's already fetched:

```scrut
$ git splice merge vendor/pkg-a
ok   vendor/pkg-a: merged 703b936
```

The commit `merge` made is `vendor/pkg-a`'s new
[boundary](boundary.md), B, and its `.splice` records the fetched branch,
T, as the new synced commit, U:

```scrut
$ git log -1 --stat --format=%s
splice: merge vendor/pkg-a from main at 703b936

 vendor/pkg-a/.splice  | 2 +-
 vendor/pkg-a/file.txt | 1 +
 2 files changed, 2 insertions(+), 1 deletion(-)
```

```scrut
$ git config --file vendor/pkg-a/.splice splice.commit
703b9360f7ac335a1134e9b5771a90a7c09ba39a
```

The upstream's commits stay upstream, and in `refs/splices/`. The
monorepo's history stays linear.

`--bump` also records the upstream branch in `.splice` when there's
nothing to merge, e.g. right after a push. Use it sparingly; see
[bumping the sync point](bump.md).
