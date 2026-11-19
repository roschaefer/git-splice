# Scenario: retrained-upstream

The upstream changed a file it stores in Git LFS. `pull` fetches the new
commit, downloads the new content from the upstream's LFS server, and
merges. [Step by step](step-by-step.md) shows each part, and
[without the content](without-content.md) how to leave it out.

- **Monorepo (`vendor/a/`)**: [cloned](../README.md), with version 1 of
  `model.bin`.
- **Upstream** (`file://$UPSTREAM`): one commit more, with version 2 of
  `model.bin`.

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
ok   vendor/a: pulled 3752e56
```

```scrut
$ cat vendor/a/model.bin
weights, version 2
```
