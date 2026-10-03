# Scenario: diverged-then-pulled

Both sides changed different files, then upstream's change was pulled in.
The local change is still waiting to be pushed.

- **Monorepo (`vendor/a`)**: cloned at `seed`, a local commit adding
  `local.txt`, then `git splice pull`, which merged cleanly.
- **Upstream**: `seed`, then a commit adding `upstream.txt`. It has never
  seen `local.txt`.

The pull's commit is the boundary, and its folder differs from the synced
commit: it contains `local.txt`. So the push rebuilds the pull as a merge
of the local commit with upstream's, and the local commit keeps its own
identity upstream.

## Output

`scenario_diverged_then_pulled` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_diverged_then_pulled
```
-->

```scrut
$ git splice status
ok   vendor/a -> main (push)
 local.txt | 1 +
 1 file changed, 1 insertion(+)
```

```scrut
$ git splice log
===  vendor/a (main)
< 1c41ddd splice: pull vendor/a from main at 9887ec6  (Test <test@example.com>)
< c013d32 local change  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed 1c41ddd to main
```

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s main
*   splice: pull vendor/a from main at 9887ec6
|\  
| * upstream change
* | local change
|/  
* seed
```
