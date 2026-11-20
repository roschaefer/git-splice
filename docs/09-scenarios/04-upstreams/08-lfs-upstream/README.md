# Scenario: lfs-upstream

The upstream stores a file in [Git LFS](https://git-lfs.com/). Git holds
only a pointer to the file's content; the content lives on the
upstream's LFS server. The monorepo's LFS server doesn't have it, so
`clone` downloads it from the upstream's server before the checkout.
[Step by step](01-cloned/01-retrained-upstream/step-by-step.md) shows
each part.

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

```scrut
$ git splice clone "file://$UPSTREAM" vendor/a
===  vendor/a: fetching file://$UPSTREAM
ok   vendor/a: cloned 18f6ff7 from main
```

```scrut
$ cat vendor/a/model.bin
weights, version 1
```

The monorepo's push uploads the content to the monorepo's LFS server:

```scrut
$ git push -q origin main
```

and a colleague's plain `git clone` of the monorepo gets the file,
without `git-splice`:

```scrut
$ git clone -q https://git.example.com/monorepo.git ../colleague && cat ../colleague/vendor/a/model.bin
weights, version 1
```
