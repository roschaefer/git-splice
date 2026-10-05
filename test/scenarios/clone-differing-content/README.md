# Scenario: clone-differing-content

A folder maintained by hand, and an upstream with different content.

- **Monorepo (`vendor/a`)**: `file.txt` and `local.txt`.
- **Upstream**: `file.txt` with other content, and `upstream.txt`.

The two share no history, so there is no merge base but an empty folder.
`clone` refuses, unless `--merge` is given: then every file that differs is
a conflict, and nothing is lost.

## Output

`scenario_clone_differing_content` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_clone_differing_content
```
-->

```scrut
$ git splice clone "$UPSTREAM" vendor/a
===  vendor/a: fetching $UPSTREAM
!!   vendor/a exists and differs from 'main' upstream -- '--merge' keeps both, and every file that differs becomes a conflict to resolve
[1]
```

```scrut
$ git splice clone --merge "$UPSTREAM" vendor/a
===  vendor/a: fetching $UPSTREAM
Auto-merging vendor/a/file.txt
CONFLICT (add/add): Merge conflict in vendor/a/file.txt
!!   vendor/a: conflict -- resolve it, then 'git commit' (or 'git cherry-pick --abort' to give up)
!!   vendor/a: clone failed
[1]
```

Files only one side has are kept, the file both have conflicts:

```scrut
$ git status --short
A  vendor/a/.splice
AA vendor/a/file.txt
A  vendor/a/upstream.txt
```

```scrut
$ echo "both versions" >vendor/a/file.txt && git add vendor/a/file.txt && git commit -q --no-edit
```

```scrut
$ git splice status
ok   vendor/a -> main (push: ahead 2)
```
