# Push before the fetch

In the [same state](README.md), a fresh clone after `init`, a push before
the first fetch says it creates the upstream branch, though the upstream
has it already. It sends nothing new: the rebuild produces the two commits
the upstream has, so the upstream stays as it was. This is part of
[#11](https://github.com/roschaefer/git-splice/issues/11).

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_init_then_cloned
```

```scrut
$ git splice push lib/a
??   lib/a: upstream has no 'main' branch yet -- this push creates it
ok   lib/a: pushed f9832ad to main
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
second version
splice: init lib/a
```

A successful push records what the upstream has now, so the clone sees it
as up to date even without a fetch:

```scrut
$ git splice status
ok   lib/a -> main (up to date)
```
