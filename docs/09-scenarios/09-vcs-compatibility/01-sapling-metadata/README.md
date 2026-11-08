# Scenario: Sapling sync metadata after a Git squash

Both monorepos imported a library, then tried its next release on a
`release` branch. The release adds `src/compat.txt`. One uses Sapling's
commit metadata; the other uses `.splice`.

A Git squash keeps the files but drops Sapling's metadata. A later release
removes the file. With the old sync record as its base, Sapling interprets
the file as a local addition and keeps it. `.splice` keeps the newer base,
so `git-splice` can apply the deletion.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds both monorepos before the squash:

```scrut
$ build_scenario scenario_sapling_metadata
```

<!--
```scrut
$ [[ "$(uname -s)" == Linux ]] || exit 80
```
-->

```scrut
$ sl --version 2>/dev/null | head -1
Sapling 0.2.20260929-102736+288e0c2d
```

Sapling's `release` commit has the new sync record:

```scrut
$ sl subtree inspect
{
  "xmerges": [
    {
      "version": 1,
      "url": "https://git.example.com/lib.git",
      "from_commit": "3bc7f68f0194869b6187f08d32f67bc1b585da06",
      "from_path": "",
      "to_path": "vendor/lib"
    }
  ]
}
```

Squash it with Git:

```scrut
$ git switch -q main &&
>   git merge -q --squash release &&
>   git commit -q -m "squash release"
Squash commit -- not updating HEAD
```

```scrut
$ sl subtree inspect
no subtree metadata found for commit 745eec9ff36d
```

The commands now run in the monorepo using `git-splice`:

```scrut
$ cd ../splice-monorepo
```

The same squash keeps the `.splice` file's new sync point:

```scrut
$ git switch -q main &&
>   git merge -q --squash release &&
>   git commit -q -m "squash release"
Squash commit -- not updating HEAD
```

```scrut
$ git config --file vendor/lib/.splice splice.commit
3bc7f68f0194869b6187f08d32f67bc1b585da06
```

The library removes `compat.txt` in the next release:

```scrut
$ git clone -q "$UPSTREAM" ../lib-dev &&
>   git -C ../lib-dev rm -q src/compat.txt &&
>   git -C ../lib-dev commit -q -m "release drops compat" &&
>   git -C ../lib-dev push -q
```

The commands now run in the monorepo using Sapling:

```scrut
$ cd ../monorepo
```

Sapling finds the record before the squashed release and keeps the file:

```scrut
$ sl subtree merge --url https://git.example.com/lib.git \
>   -r "$(git --git-dir="$UPSTREAM" rev-parse main)" --to-path vendor/lib
using cached git repo at $VCS_ROOT/sapling-cache/gitrepos/316067af85b8bd24e96f811d9f55a8f2d20eed8dcae7796fe42d9eb9ea621a17
pulling '18fd6f7bfdc2047f0641984b501e3373d55c895f' from 'https://git.example.com/lib.git'
searching for merge base ...
found the last subtree import commit 0318bf4fb04d
merge base: 24e77474eea7
update complete
(subtree merge, don't forget to commit)
```

```scrut
$ ls vendor/lib/src
compat.txt
parse.txt
```

The commands now run in the monorepo using `git-splice`:

```scrut
$ cd ../splice-monorepo
```

The newer sync point lets the pull remove the file:

```scrut
$ git splice pull vendor/lib
ok   vendor/lib fetched (main moved 3bc7f68..18fd6f7)
ok   vendor/lib: pulled 18fd6f7
```

```scrut
$ ls vendor/lib/src
parse.txt
```
