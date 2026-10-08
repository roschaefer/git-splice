# Scenario: edited-before-push: a change before the pull

The same edit as in [edited-before-push](README.md), but the next change
comes before the `pull`. Then the folder no longer has the pushed
commit's files, so nothing tells the edit apart from a divergence. R
still starts at the synced commit with the original commit, and the
next push publishes it, next to the edited one.

The way out would be `git splice pull -s ours`: record the upstream's
tip as the synced commit, keep the monorepo's files, and build on top of
it ([#82](https://github.com/roschaefer/git-splice/issues/82)). It isn't
implemented yet.

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

Edit and push, as in [edited-before-push](README.md#edit-and-push):

```scrut
$ R="$(git splice log --graph vendor/a | awk '$3 == "(R)" { print $2 }')" && git worktree add -q -b edited ../edited "$R"
```

```scrut
$ git -C ../edited commit -q --amend -m "fix the parser" && git -C ../edited push -q "$UPSTREAM" edited:main && git splice fetch
ok   vendor/a fetched (main moved bde4164..ce80186)
```

The next change, before any pull:

```scrut
$ echo "another fix" >>vendor/a/file.txt && git commit -q -a -m "another fix"
```

R still starts at the synced commit with the original commit. `log`
marks it and the edited commit `=`, the same change on both sides, but
the rebuild doesn't skip it, so the splice has diverged:

```scrut
$ git splice log vendor/a
===  vendor/a (main)
< 294db54 another fix  (Test <test@example.com>)
= ce80186 fix the parser  (Test <test@example.com>)
= 700a8ff fix, see INTERNAL-123  (Test <test@example.com>)
```

The pull merges from the synced commit, where both sides added the same
line, so it conflicts. Keeping the monorepo's side resolves it:

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
