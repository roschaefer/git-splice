# Scenario: diverged-common-ancestor

Both sides moved independently since the subtree was added, but they still
share a real sync point: the add commit itself.

- **Monorepo (`vendor/a`)**: added at `seed`, then one local commit
  under `vendor/a`.
- **Remote**: `seed`, then one independent upstream commit.
- **Common ancestor**: yes -- `seed`, the point they were added at.

This is the "ordinary" divergence case: `git subtrees pull` still attempts
its normal `git subtree pull --squash`, which may hit a normal merge
conflict resolved by editing the file and running plain `git commit`.
Contrast with `diverged-unrelated-history`, where no such attempt is made.

## Output

`scenario_diverged_common_ancestor` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_diverged_common_ancestor
```
-->

```scrut
$ git subtrees status
ok   vendor/a -> $UPSTREAM (diverged)
 file.txt | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```

```scrut
$ git subtrees pull
ok   vendor/a fetched
Auto-merging vendor/a/file.txt
CONFLICT (content): Merge conflict in vendor/a/file.txt
Automatic merge failed; fix conflicts and then commit the result.
!!   vendor/a: pull failed -- resolve any conflicts, 'git commit', then re-run pull
!!   Failed: vendor/a
[1]
```

From here, resolve the conflict, `git commit` and push, as in the
[diverged history walkthrough](../../../walkthrough/diverged.md).
