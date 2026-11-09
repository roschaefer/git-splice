# Scenario: retrained-upstream

> **Known bug, [#407](https://github.com/roschaefer/git-splice/issues/407).** This page shows what `git-splice` does today, bug included. See [all known bugs](../../../../99-known-bugs.md).

The upstream changed a file it stores in Git LFS, and `pull` fails the
way [`clone`](../../README.md) does: Git LFS looks for the new content on
the monorepo's LFS server. `git-splice` doesn't support Git LFS yet,
[#407](https://github.com/roschaefer/git-splice/issues/407). Pulling by
hand works, as [cloning by hand](../../clone-by-hand.md) does.

- **Monorepo (`vendor/a/`)**: [cloned by hand](../README.md), with
  version 1 of `model.bin`.
- **Upstream** (`file://$UPSTREAM`): one commit more, with version 2 of `model.bin`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../../readme-setup.sh" && export GIT_CONFIG_GLOBAL="$PWD/.gitconfig" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$PWD/monorepo.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/monorepo.git && git lfs install --skip-repo >/dev/null
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_retrained_upstream
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved 18f6ff7..3752e56)
Downloading vendor/a/model.bin (19 B)
Error downloading object: vendor/a/model.bin (6c93425): Smudge error: Error downloading vendor/a/model.bin (6c93425e5465e1c1cfe0a87e974b4930f5899422f82b34d8092f3e148b7d4cc4): error transferring "6c93425e5465e1c1cfe0a87e974b4930f5899422f82b34d8092f3e148b7d4cc4": [0] remote missing object 6c93425e5465e1c1cfe0a87e974b4930f5899422f82b34d8092f3e148b7d4cc4

Errors logged to '.*/monorepo/\.git/lfs/logs/.*\.log'\. (regex)
Use `git lfs logs last` to view the log.
error: external filter 'git-lfs filter-process' failed
fatal: vendor/a/model.bin: smudge filter lfs failed
!!   vendor/a: pull failed
!!   Failed: vendor/a
[1]
```

The failed pull leaves `.splice` changed and `model.bin` deleted, and
the next pull refuses to overwrite them:

```scrut
$ git status --short
 M vendor/a/.splice
 D vendor/a/model.bin
```

Putting the splice back as it was, a pull that leaves the content
behind goes through:

```scrut
$ git checkout -q -- vendor/a
```

```scrut
$ GIT_LFS_SKIP_SMUDGE=1 git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled 3752e56
```

and the content comes from the upstream's LFS server, as for the clone:

```scrut
$ git lfs fetch "file://$UPSTREAM" "refs/splices/$(git splice key vendor/a)/heads/main"
Fetching reference refs/splices/upstream/heads/main
```

```scrut
$ git lfs checkout vendor/a
```

```scrut
$ cat vendor/a/model.bin
weights, version 2
```
