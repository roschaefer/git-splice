# retrained-upstream: step by step

A file stored in Git LFS lives in two places:

- **In Git**, the commit holds a small *pointer*: the content's SHA-256
  and size.
- **On an LFS server**, the content itself. Each repository has its own:
  the upstream's has version 2 of `model.bin`, the monorepo's doesn't.

Between the two sits the local LFS store, `.git/lfs/objects/`:

- On a checkout, Git LFS's *smudge* filter replaces each pointer with
  its content from the local store. If the content isn't there, it asks
  the LFS server of the repository's own remote: here the monorepo's,
  which doesn't have version 2.
- On a `git push`, Git LFS's `pre-push` hook uploads the content of the
  pushed commits from the local store to the server of the remote it
  pushes to.

So `fetch` downloads the content of the commit a merge would check out
from the upstream's LFS server into the local store, right after it
fetches the commits. `merge` then finds it there and needs no network,
as for the commits.

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

### Fetch

```scrut
$ git splice fetch vendor/a
ok   vendor/a fetched (main moved 18f6ff7..3752e56)
```

The fetched commit holds the pointer to version 2:

```scrut
$ git show "refs/splices/$(git splice key vendor/a)/heads/main:model.bin"
version https://git-lfs.github.com/spec/v1
oid sha256:6c93425e5465e1c1cfe0a87e974b4930f5899422f82b34d8092f3e148b7d4cc4
size 19
```

Its content is in the local store now, under its SHA-256:

```scrut
$ ls .git/lfs/objects/6c/93/
6c93425e5465e1c1cfe0a87e974b4930f5899422f82b34d8092f3e148b7d4cc4
```

### Merge

The checkout finds version 2 in the local store:

```scrut
$ git splice merge vendor/a
ok   vendor/a: merged 3752e56
```

```scrut
$ cat vendor/a/model.bin
weights, version 2
```

The monorepo's commit holds the same pointer:

```scrut
$ git show HEAD:vendor/a/model.bin
version https://git-lfs.github.com/spec/v1
oid sha256:6c93425e5465e1c1cfe0a87e974b4930f5899422f82b34d8092f3e148b7d4cc4
size 19
```

```scrut
$ git status --short
```

### The monorepo's push

The monorepo's own push uploads version 2 from the local store to the
monorepo's LFS server:

```scrut
$ git push -q origin main
```

so a colleague's plain `git clone` gets it, without `git-splice`:

```scrut
$ git clone -q https://git.example.com/monorepo.git ../colleague && cat ../colleague/vendor/a/model.bin
weights, version 2
```
