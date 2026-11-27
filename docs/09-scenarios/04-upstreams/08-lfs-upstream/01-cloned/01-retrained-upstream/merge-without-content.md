# retrained-upstream: merge without the content

`merge` downloads nothing: `fetch` does. A fetch with
`GIT_LFS_SKIP_SMUDGE=1` leaves the content out, and a merge without it
would need it for the checkout. Git LFS would then ask the monorepo's LFS
server, which gets the content only with the monorepo's push, so the
merge refuses before it changes anything.

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
$ GIT_LFS_SKIP_SMUDGE=1 git splice fetch vendor/a
ok   vendor/a fetched (main moved 18f6ff7..3752e56)
```

```scrut
$ git splice merge vendor/a
!!   vendor/a: the Git LFS content of vendor/a/model.bin in 3752e56 isn't here -- 'git splice fetch vendor/a' downloads it
!!   Failed: vendor/a
[1]
```

```scrut
$ git status --short
```

A fetch downloads the content, and the merge checks it out:

```scrut
$ git splice fetch vendor/a
ok   vendor/a fetched
```

```scrut
$ git splice merge vendor/a
ok   vendor/a: merged 3752e56
```

```scrut
$ cat vendor/a/model.bin
weights, version 2
```
