# Push before the fetch

In the [same state](README.md), a fresh clone after `init`, a push before
the first fetch says it creates the upstream branch, though the upstream
has it already. It sends nothing new: the rebuild produces the two commits
the upstream has, so the upstream stays as it was. This is part of
[#11](https://github.com/roschaefer/git-splice/issues/11).

## Output

`scenario_init_then_cloned` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_init_then_cloned
```
-->

```scrut
$ git splice push lib/a
??   lib/a: upstream has no 'main' branch yet -- this push creates it
ok   lib/a: pushed ef82a18 to main
```

```scrut
$ git -C "$UPSTREAM" log --format=%s main
second version
first version
```

A successful push records what the upstream has now, so the clone sees it
as up to date even without a fetch:

```scrut
$ git splice status
ok   lib/a -> main (up to date)
```
