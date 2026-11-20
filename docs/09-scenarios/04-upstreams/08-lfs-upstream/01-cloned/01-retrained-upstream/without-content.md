# retrained-upstream: without the content

`GIT_LFS_SKIP_SMUDGE=1` tells Git LFS to check out pointers instead of
content. `git-splice` then doesn't download the content either.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../../readme-setup.sh" && export GIT_CONFIG_GLOBAL="$PWD/.gitconfig" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$PWD/monorepo.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/monorepo.git && git lfs install --skip-repo >/dev/null
```
-->

[`setup.bash`](setup.bash) builds the same state as
[`README.md`](README.md): the monorepo has version 1 of `model.bin`, and
the upstream has version 2.

```scrut
$ build_scenario scenario_retrained_upstream
```

```scrut
$ GIT_LFS_SKIP_SMUDGE=1 git splice pull vendor/a
ok   vendor/a fetched (main moved 18f6ff7..3752e56)
ok   vendor/a: pulled 3752e56
```

The file is the pointer:

```scrut
$ cat vendor/a/model.bin
version https://git-lfs.github.com/spec/v1
oid sha256:6c93425e5465e1c1cfe0a87e974b4930f5899422f82b34d8092f3e148b7d4cc4
size 19
```

The monorepo can't be pushed like this: its LFS server would get a
pointer to content nobody gave it.

```scrut
$ git push -q origin main
Git LFS upload failed:
  (missing) vendor/a/model.bin (6c93425e5465e1c1cfe0a87e974b4930f5899422f82b34d8092f3e148b7d4cc4)
hint: Your push was rejected due to missing or corrupt local objects.
hint: You can disable this check with: `git config lfs.allowincompletepush true`
error: failed to push some refs to 'file://.*/monorepo\.git' (regex)
[1]
```

A fetch without `GIT_LFS_SKIP_SMUDGE` downloads the content, and `git
lfs checkout` replaces the pointer with it:

```scrut
$ git splice fetch vendor/a
ok   vendor/a fetched
```

```scrut
$ git lfs checkout vendor/a
```

```scrut
$ cat vendor/a/model.bin
weights, version 2
```

```scrut
$ git push -q origin main
```
