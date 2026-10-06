# Scenario: clone-without-commits

A brand-new monorepo without any commits.

A clone is a commit on top of HEAD, so it needs one to exist. The command
stops before fetching or changing the worktree and explains how to create
that first commit.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_clone_without_commits
```

```scrut
$ git splice clone "$UPSTREAM" vendor/a
!!   branch 'main' has no commits yet -- create one and re-run: git commit --allow-empty -m 'initial commit'
[1]
```

```scrut
$ git commit -q --allow-empty -m "initial commit" && git splice clone "$UPSTREAM" vendor/a
===  vendor/a: fetching $UPSTREAM
ok   vendor/a: cloned bde4164 from main
```
