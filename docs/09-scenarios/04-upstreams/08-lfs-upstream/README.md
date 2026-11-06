# Scenario: lfs-upstream

> **Known bug, [#407](https://github.com/roschaefer/git-splice/issues/407).** This page shows what `git-splice` does today, bug included. See [all known bugs](../../08-known-bugs.md).

The upstream stores a file in [Git LFS](https://git-lfs.com/), and
`clone` fails: Git LFS looks for the file's content on the monorepo's
LFS server, which doesn't have it. `git-splice` doesn't support Git LFS
yet, [#407](https://github.com/roschaefer/git-splice/issues/407).
[Cloning by hand](clone-by-hand.md) works.

- **Monorepo**, on `main`: one commit, pushed to its own remote,
  `https://git.example.com/monorepo.git`.
- **Upstream** (`file://$UPSTREAM`): `model.bin`, stored in Git LFS, as
  its `.gitattributes` says.

Git LFS is installed, as `git lfs install` sets it up. The upstream is
named by its `file://` URL, as Git LFS transfers content to and from a
local repository only through those.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh" && export GIT_CONFIG_GLOBAL="$PWD/.gitconfig" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$PWD/monorepo.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/monorepo.git && git lfs install --skip-repo >/dev/null
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_lfs_upstream
```

`clone` fetches the upstream's commits, but not the content Git LFS
keeps apart from them. The checkout asks the monorepo's LFS server for
it, and fails:

```scrut
$ git splice clone "file://$UPSTREAM" vendor/a
===  vendor/a: fetching file://$UPSTREAM
Downloading vendor/a/model.bin (19 B)
Error downloading object: vendor/a/model.bin (824c087): Smudge error: Error downloading vendor/a/model.bin (824c08711f4323285490080552966d5b256f5793cd45f70ce97878b7fa81e70a): error transferring "824c08711f4323285490080552966d5b256f5793cd45f70ce97878b7fa81e70a": [0] remote missing object 824c08711f4323285490080552966d5b256f5793cd45f70ce97878b7fa81e70a

Errors logged to '.*/monorepo/\.git/lfs/logs/.*\.log'\. (regex)
Use `git lfs logs last` to view the log.
error: external filter 'git-lfs filter-process' failed
fatal: vendor/a/model.bin: smudge filter lfs failed
!!   vendor/a: clone failed
[1]
```

The failed clone leaves its files behind, untracked:

```scrut
$ git status --short
?? vendor/
```
