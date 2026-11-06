# lfs-upstream: clone by hand

`clone` of an upstream that stores files in Git LFS
[fails](README.md). Until `git-splice` supports Git LFS
([#407](https://github.com/roschaefer/git-splice/issues/407)), three
commands do what it would: clone without the content, fetch the content
from the upstream's LFS server, and check it out.

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

`GIT_LFS_SKIP_SMUDGE=1` makes the checkout leave the files Git LFS
stores as they are committed, as pointers to their content:

```scrut
$ GIT_LFS_SKIP_SMUDGE=1 git splice clone "file://$UPSTREAM" vendor/a
===  vendor/a: fetching file://$UPSTREAM
ok   vendor/a: cloned 18f6ff7 from main
```

```scrut
$ cat vendor/a/model.bin
version https://git-lfs.github.com/spec/v1
oid sha256:824c08711f4323285490080552966d5b256f5793cd45f70ce97878b7fa81e70a
size 19
```

The monorepo can't be pushed like this: its LFS server would get a
pointer to content nobody gave it.

```scrut
$ git push -q origin main
Git LFS upload failed:
  (missing) vendor/a/model.bin (824c08711f4323285490080552966d5b256f5793cd45f70ce97878b7fa81e70a)
hint: Your push was rejected due to missing or corrupt local objects.
hint: You can disable this check with: `git config lfs.allowincompletepush true`
error: failed to push some refs to 'file://.*/monorepo\.git' (regex)
[1]
```

`git lfs fetch` downloads the content from the upstream's LFS server,
for the commit `clone` fetched:

```scrut
$ git lfs fetch "file://$UPSTREAM" "refs/splices/$(git splice key vendor/a)/heads/main"
Fetching reference refs/splices/upstream/heads/main
```

```scrut
$ git lfs checkout vendor/a
```

```scrut
$ cat vendor/a/model.bin
weights, version 1
```

Now the monorepo's push uploads the content to the monorepo's LFS
server:

```scrut
$ git push -q origin main
```

and a colleague's plain `git clone` of the monorepo gets the file,
without `git-splice`:

```scrut
$ git clone -q https://git.example.com/monorepo.git ../colleague && cat ../colleague/vendor/a/model.bin
weights, version 1
```
