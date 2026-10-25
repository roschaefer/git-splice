# Pull the PR with --rebase

In the [same state](README.md), `pull --rebase` would take *f* in as it
is, on top of *p*, and rebase *c* onto it. *f* lacks *m*, which came
from upstream's `main`, so the folder would lose `lock.txt`. Upstream's
`feature` was never rebased: the synced commit *m* is on another
upstream branch, but not on this one. So `pull --rebase` refuses, and
prints the two ways to rebase the PR: on one side only.

That differs from a branch the upstream [rewrote](../../06-rewritten-history/04-patch-branch-rebased/01-unpushed-local-commit/README.md),
which lost the synced commit with the rewrite: no other branch has it
then, and `--rebase` takes the rewritten branch in.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_feature_branch_behind_default_branch
```

```scrut
$ git splice pull --rebase vendor/a
ok   vendor/a fetched
!!   vendor/a: 'feature' lacks the synced commit 5cc5467, which this branch got from 'main' -- --rebase would drop it. To rebase 'feature' onto 'main', do it on one side only:

  # keep this branch's rebase, overwriting upstream's 'feature':
  git splice push --force -- vendor/a

  # OR: rebase or merge 'feature' onto 'main' upstream, e.g. with "Update branch" on GitHub, then:
  git splice pull -- vendor/a

!!   Failed: vendor/a
[1]
```

Nothing changed:

```scrut
$ git log --format=%s
feature change
splice: pull vendor/a from main at 5cc5467
splice: clone vendor/a from main at bde4164
initial commit
```
