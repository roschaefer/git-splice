# Scenario: clone-copied-content

A folder that was copied in by hand, with exactly upstream's content.

- **Monorepo (`vendor/a`)**: `file.txt`, identical to upstream's.
- **Upstream**: `seed`.

Nothing can be lost, so `clone` only adds `.splice`.

## Output

`scenario_clone_copied_content` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_clone_copied_content
```
-->

```scrut
$ git splice clone "$UPSTREAM" vendor/a
===  vendor/a: fetching $UPSTREAM
ok   vendor/a: cloned bde4164 from main
```

```scrut
$ git show --stat --format=%s HEAD
splice: clone vendor/a from main at bde4164

 vendor/a/.splice | 4 ++++
 1 file changed, 4 insertions(+)
```

```scrut
$ git splice status
ok   vendor/a -> main (up to date)
```
