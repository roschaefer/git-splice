# retrained-upstream: pull with an LFS hook

[`pull` fails](README.md) on an upstream that stores files in Git LFS.
Until `git-splice` downloads LFS content itself
([#407](https://github.com/roschaefer/git-splice/issues/407)), a hook run
by `--exec` can do it.

A file stored in Git LFS lives in two places:

- **In Git**, the commit holds a small *pointer*: the content's SHA-256
  and size.
- **On an LFS server**, the content itself. Each repository has its own:
  the upstream's has `model.bin`, the monorepo's doesn't yet.

Between the two sits the local LFS store, `.git/lfs/objects/`:

- `git lfs fetch <url> <ref>` downloads into it the content that the
  pointers in `<ref>`'s files name, from `<url>`'s LFS server.
- On a checkout, Git LFS's *smudge* filter replaces each pointer with
  its content from the local store. If the content isn't there, it asks
  the LFS server of the repository's own remote. That's why
  `pull` fails: the monorepo's server doesn't have version 2.
- On a `git push`, Git LFS's `pre-push` hook uploads the content of the
  pushed commits from the local store to the server of the remote it
  pushes to.

So the content has to be in the local store before `pull` checks out
the upstream's commit. The hook downloads it there, between the fetch
and the merge.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../../readme-setup.sh" && export GIT_CONFIG_GLOBAL="$PWD/.gitconfig" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$PWD/monorepo.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/monorepo.git && git lfs install --skip-repo >/dev/null
```
-->

[`setup.bash`](setup.bash) builds the same state as the
[failing pull](README.md): the monorepo has version 1 of `model.bin`, and
the upstream has version 2.

```scrut
$ build_scenario scenario_retrained_upstream
```

```scrut
$ cat vendor/a/model.bin
weights, version 1
```

### The hook

[`lfs-fetch.sh`](lfs-fetch.sh):

```scrut
$ export LFS_FETCH="$TESTDIR/lfs-fetch.sh" && cat "$LFS_FETCH"
#!/bin/sh
# A hook for 'git splice pull --exec': after pull fetches the upstreams'
# commits and before it merges them, download the Git LFS content of the
# branches it fetched, from each upstream's own LFS server.
set -e
test "$GIT_SPLICE_EVENT" = after-fetch || exit 0

git ls-files -- '*/.splice' | while read -r file; do
  path="${file%/.splice}"
  git config --file "$file" --get-regexp '^upstream\..*\.url$' |
    while read -r name url; do
      upstream="${name#upstream.}"
      upstream="${upstream%.url}"
      key="$(git splice key --upstream "$upstream" "$path")"
      git for-each-ref --format='%(refname)' "refs/splices/$key/heads/" |
        xargs -r git lfs fetch "$url"
    done
done
```

- `pull` runs the hook at each checkpoint, with the checkpoint's name in
  `GIT_SPLICE_EVENT`. The hook acts only at `after-fetch`: the upstream's
  commits are in `refs/splices/`, and nothing is checked out yet.
- For every splice, it reads the upstream URLs from the splice's
  `.splice`, and asks `git splice key` for each upstream's key. The
  branches fetched from that upstream are `refs/splices/<key>/heads/*`.
- `git lfs fetch` downloads the content those branches' files name, from
  that upstream's LFS server. Content that's in the local store already
  isn't downloaded again.

A hook must leave the repository as it was, or `pull` stops. `git lfs
fetch` writes only to `.git/lfs/`.

### The pull

```scrut
$ git splice pull --exec 'sh "$LFS_FETCH"' vendor/a
ok   vendor/a fetched (main moved 18f6ff7..3752e56)
Fetching reference refs/splices/upstream/heads/main
ok   vendor/a: pulled 3752e56
```

The merge's checkout found version 2 in the local store:

```scrut
$ cat vendor/a/model.bin
weights, version 2
```

The commit holds the pointer, as for any file stored in Git LFS:

```scrut
$ git show HEAD:vendor/a/model.bin
version https://git-lfs.github.com/spec/v1
oid sha256:6c93425e5465e1c1cfe0a87e974b4930f5899422f82b34d8092f3e148b7d4cc4
size 19
```

and the content is in the local store, under its SHA-256:

```scrut
$ ls .git/lfs/objects/6c/93/
6c93425e5465e1c1cfe0a87e974b4930f5899422f82b34d8092f3e148b7d4cc4
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

so a colleague's plain `git clone` gets it, without `git-splice` and
without the hook:

```scrut
$ git clone -q https://git.example.com/monorepo.git ../colleague && cat ../colleague/vendor/a/model.bin
weights, version 2
```

## Limits

- `clone` has no `--exec`. A first clone still goes
  [by hand](../../clone-by-hand.md).
- The hook asks each upstream's LFS server at the URL Git LFS derives
  from the upstream's URL. An upstream whose `.lfsconfig` names another
  LFS server isn't covered.
