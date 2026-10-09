# Scenario: edited-before-push

The commits a push would send, R, are edited before they're pushed:
here, a message that names an internal ticket is reworded. They're
pushed with plain Git, and the monorepo isn't told. Then R, which is
computed from the monorepo's history, still has the original commit, and
publishes it with the next push, next to the edited one.

- **Monorepo (`vendor/a`)**: cloned at `seed`, then the unpushed commit
  `fix, see INTERNAL-123`.
- **Upstream**: `seed`.

The recipe:

1. Get R: `git splice rebuild` prints it.
2. Check it out in a worktree of its own: R has the upstream's layout,
   and a `git switch` would replace the monorepo's whole checkout.
3. Edit the commits after the synced commit U, e.g. with
   `git rebase -i`, and push the result with `git push`.
4. **Record the pushed commit as the new sync point.** Without this step,
   the monorepo keeps rebuilding the original commits: this document
   shows what happens then. [record-the-sync-point](record-the-sync-point.md)
   shows the recipe with it.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_edited_before_push
```

### Edit and push

```scrut
$ R="$(git splice rebuild vendor/a)" && git log --oneline "$R"
700a8ff fix, see INTERNAL-123
bde4164 seed
```

```scrut
$ git worktree add -q -b edited ../edited "$R" && ls -A ../edited
.git
file.txt
```

```scrut
$ git -C ../edited commit -q --amend -m "fix the parser" && git -C ../edited push -q "$UPSTREAM" edited:main
```

The upstream has the edited commit, and the monorepo's folder has the
same files, so the splice reads as up to date:

```scrut
$ git splice fetch && git splice status
ok   vendor/a fetched (main moved bde4164..ce80186)
ok   vendor/a -> main (up to date)
```

A plain `pull` doesn't change that: there's nothing to merge, and it
records no new sync point
([#17](https://github.com/roschaefer/git-splice/issues/17) is the same
gap, for an upstream rewritten by someone else):

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: nothing to pull
```

### The original comes back

The next change in the monorepo:

```scrut
$ echo "another fix" >>vendor/a/file.txt && git commit -q -a -m "another fix"
```

R still starts at U with the original commit. `log` marks it and the
edited commit `=`, the same change on both sides, but the rebuild
doesn't skip it, so the splice has diverged:

```scrut
$ git splice log vendor/a
===  vendor/a (main)
< 294db54 another fix  (Test <test@example.com>)
= ce80186 fix the parser  (Test <test@example.com>)
= 700a8ff fix, see INTERNAL-123  (Test <test@example.com>)
```

The pull merges from U, where both sides added the same line, so it
conflicts. Keeping the monorepo's side resolves it:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched
Auto-merging vendor/a/file.txt
CONFLICT (content): Merge conflict in vendor/a/file.txt
!!   vendor/a: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)
!!   vendor/a: pull failed
!!   Failed: vendor/a
[1]
```

```scrut
$ git checkout -q --ours vendor/a/file.txt && git add vendor/a/file.txt && git commit -q --no-edit
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 623a43e to main
```

The upstream now has both: the edited commit, and the original with the
message that was meant to stay in the monorepo:

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s main
*   splice: pull vendor/a from main at ce80186
|\  
| * fix the parser
* | another fix
* | fix, see INTERNAL-123
|/  
* seed
```
