# Scenario: edited-before-push: record the sync point

The same edit as in [edited-before-push](README.md), with its last step:
the pushed commit becomes the new sync point. The monorepo then builds on
the edited commit, and the original never reaches the upstream.

There's no command for that step yet. `git splice pull --ours` would
record the upstream's tip as the sync point and keep the monorepo's
files ([#82](https://github.com/roschaefer/git-splice/issues/82)). Here
it's done by hand, in `.splice`. That's safe only because the folder's
files are exactly the pushed commit's: the edit changed a message, not a
file.

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
$ R="$(git splice rebuild vendor/a)" && git worktree add -q -b edited ../edited "$R"
```

```scrut
$ git -C ../edited commit -q --amend -m "fix the parser" && git splice push --rebuild edited vendor/a
ok   vendor/a: pushed ce80186 to main
```

Record the pushed commit as the sync point, in a commit that changes
only `.splice`:

```scrut
$ git config --file vendor/a/.splice splice.commit "$(git rev-parse edited)" && git commit -q -a -m "record the edited push as the sync point"
```

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```

The next change builds on the edited commit:

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
