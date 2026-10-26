# Scenario: push-ahead

Only the monorepo changed since the clone.

<div align="center">

![The monorepo commit a clones the upstream commit k, T; b changes the folder, rebuilt as b prime, R, dashed](ahead.drawio.svg)

</div>

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_push_ahead
```

<!--
```scrut
$ k="$(git config --file vendor/a/.splice splice.commit)" &&
>   check_drawing "$TESTDIR/ahead.drawio.svg" k="$k" a=HEAD~1 b=HEAD
ok   ahead.drawio.svg: 4 commits, 5 arrows, 3 boxes, 1 lanes
```
-->

```scrut
$ git splice status
On branch main

  ahead 1  vendor/a
```

`log` shows the commit a push would publish, and who wrote it:

```scrut
$ git splice log
===  vendor/a (main)
< e859a6b local change  (Test <test@example.com>)
```

`push` sends it. Nothing is written to the monorepo:

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed e859a6b to main
```

```scrut
$ git splice status
On branch main

  up to date  vendor/a
```
