# Scenario: bisect-into-a-pull

`git bisect` in the monorepo ends at a pull X. A pull splices upstream
changes in as one commit, so the bug came in with one of the upstream
commits squashed into it. Which one?

- **Upstream**: `seed`, then three commits: `add config.txt`,
  `log at debug level` and `fix a typo`.
- **Monorepo**: `vendor/a` spliced in at `seed`, then `check.sh`, a
  test outside the splice that fails when the library logs at debug
  level. Then a pull of the three upstream commits, and one more commit.

The upstream's own history has no test for it: the bug only shows in
the monorepo. So the upstream commits are tested inside the monorepo, as
it was right before the pull.

## Output

[`setup.bash`](setup.bash) builds this state:

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

```scrut
$ build_scenario scenario_bisect_into_a_pull
```

### Bisect the monorepo

```scrut
$ git log --format=%s
add notes
splice: pull vendor/a from main at 803779d
add check.sh
add vendor/a
initial commit
```

The root commit is the known good one:

```scrut
$ git bisect start HEAD "$(git rev-list --max-parents=0 HEAD)" >/dev/null && git bisect run ./check.sh >/dev/null && git show --stat --format='first bad commit: %s' refs/bisect/bad
first bad commit: splice: pull vendor/a from main at 803779d

 vendor/a/.splice    | 2 +-
 vendor/a/config.txt | 1 +
 vendor/a/file.txt   | 2 +-
 3 files changed, 3 insertions(+), 2 deletions(-)
```

The first bad commit is the pull X. It has the changes of three upstream
commits in one.

```scrut
$ X="$(git rev-parse refs/bisect/bad)" && git bisect reset >/dev/null
```

### The upstream commits in the pull

`.splice` records the synced commit: U1 before the pull, in X's first
parent, and U2 after it, in X. The commits between them came in with X.
The fetched upstream refs have them:

```scrut
$ U1="$(git config --blob "$X^:vendor/a/.splice" splice.commit)" && U2="$(git config --blob "$X:vendor/a/.splice" splice.commit)" && git log --oneline "$U1..$U2"
803779d fix a typo
83019ad log at debug level
4192552 add config.txt
```

[#109](https://github.com/roschaefer/git-splice/issues/109) proposes
`git splice show <commit>` to print them.

### Bisect the upstream commits inside the monorepo

Two worktrees: `../before`, the monorepo right before the pull, and
`../lib`, the upstream at U2. U1 and U2 have the upstream's layout, so
they need a worktree of their own.

```scrut
$ git worktree add -q --detach ../before "$X^" && git worktree add -q --detach ../lib "$U2" && cd ../lib
```

Bisect runs in `../lib`. For each candidate, it copies the candidate's
files into `../before/vendor/a` and runs the monorepo's test there:

```scrut
$ git bisect start "$U2" "$U1" && git bisect run sh -c 'git --work-tree=../before/vendor/a checkout -f HEAD -- . && cd ../before && ./check.sh'
Bisecting: 0 revisions left to test after this (roughly 1 step)
[83019adee0a2cf37e98fc79274ba471a0ba8f99a] log at debug level
running 'sh' '-c' 'git --work-tree=../before/vendor/a checkout -f HEAD -- . && cd ../before && ./check.sh'
Bisecting: 0 revisions left to test after this (roughly 0 steps)
[419255245bf628a762cb138a18347abd227d07e7] add config.txt
running 'sh' '-c' 'git --work-tree=../before/vendor/a checkout -f HEAD -- . && cd ../before && ./check.sh'
83019adee0a2cf37e98fc79274ba471a0ba8f99a is the first bad commit
commit 83019adee0a2cf37e98fc79274ba471a0ba8f99a
Author: Upstream <upstream@example.com>
Date:   Thu Jan 1 00:00:00 2026 +0000

    log at debug level

 config.txt | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
bisect found first bad commit
```

That's the exact upstream commit. If the bug shows in the upstream
alone, `git bisect run` in `../lib` without `../before` is enough.

The copy leaves files in the folder that a candidate doesn't have, e.g.
ones an upstream commit deleted. And if X merged local changes into the
folder, the candidates are tested without them.
[#110](https://github.com/roschaefer/git-splice/issues/110) proposes
`git splice expand`, which would turn X into one monorepo commit per
upstream commit, so that `git bisect` continues in the monorepo itself.
