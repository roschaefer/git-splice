# Scenario: edited-before-push

The commits a push would send, R, are edited before they're pushed:
here, a message that names an internal ticket is reworded. They're
pushed with plain Git. R is computed from the monorepo's history, which
still has the original commit, so a `pull` right after the push records
the edited commit as the synced commit. From there on, the monorepo
builds on the edited commit.

- **Monorepo (`vendor/a`)**: cloned at `seed`, then the unpushed commit
  `fix, see INTERNAL-123`.
- **Upstream**: `seed`.

The recipe:

1. Get R. `git splice rebuild` would print it
   ([#54](https://github.com/roschaefer/git-splice/issues/54)); until
   then, `log --graph` shows it, labeled `(R)`.
2. Check it out in a worktree of its own: R has the upstream's layout,
   and a `git switch` would replace the monorepo's whole checkout.
3. Edit the commits after the synced commit U, e.g. with
   `git rebase -i`, and push the result with `git push`. Change only the
   history, not the files.
4. **`git splice pull`**, before the next change to the splice. The
   folder has the pushed commit's files, so the pull records it as the
   synced commit. A change before the pull publishes the original commit
   after all: [change-before-the-pull](change-before-the-pull.md).

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
$ R="$(git splice log --graph vendor/a | awk '$3 == "(R)" { print $2 }')" && git log --oneline "$R"
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

### Pull

The folder has the upstream's files, but R still has the original
commit, not the edited one. The pull records the edited commit, in a
commit that changes only `.splice`:

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved bde4164..ce80186)
ok   vendor/a: recorded ce80186 as the synced commit -- the folder already has its files
```

```scrut
$ git show --stat --format=%s HEAD
splice: pull vendor/a from main at ce80186

 vendor/a/.splice | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```

### The next change builds on the edited commit

```scrut
$ echo "another fix" >>vendor/a/file.txt && git commit -q -a -m "another fix"
```

```scrut
$ git splice log vendor/a
===  vendor/a (main)
< bbd5c31 another fix  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed bbd5c31 to main
```

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s main
* another fix
* fix the parser
* seed
```
