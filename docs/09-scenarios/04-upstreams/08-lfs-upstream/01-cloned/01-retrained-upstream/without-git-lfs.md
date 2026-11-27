# retrained-upstream: without Git LFS set up

Where Git LFS isn't set up, a checkout keeps the pointers, as it does in
any Git repository. `git-splice` then downloads nothing, and says so.

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

`git lfs uninstall` removes Git LFS's filter from the global Git
configuration, and a checkout without it writes the pointer that Git
has, like the checkout of someone who never set up Git LFS:

```scrut
$ git lfs uninstall --skip-repo
Global Git LFS configuration has been removed.
```

```scrut
$ git checkout -- vendor/a/model.bin && cat vendor/a/model.bin
version https://git-lfs.github.com/spec/v1
oid sha256:824c08711f4323285490080552966d5b256f5793cd45f70ce97878b7fa81e70a
size 19
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved 18f6ff7..3752e56)
??   vendor/a: 3752e56 stores files in Git LFS, and checkouts here keep them as pointers
ok   vendor/a: pulled 3752e56
```

The file is the new pointer, and the content isn't here:

```scrut
$ cat vendor/a/model.bin
version https://git-lfs.github.com/spec/v1
oid sha256:6c93425e5465e1c1cfe0a87e974b4930f5899422f82b34d8092f3e148b7d4cc4
size 19
```

```scrut
$ test -e .git/lfs/objects/6c/93/6c93425e5465e1c1cfe0a87e974b4930f5899422f82b34d8092f3e148b7d4cc4 || echo "not in the local LFS store"
not in the local LFS store
```
