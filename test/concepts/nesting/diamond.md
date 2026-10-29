# Diamond

Two apps, each in a repository of its own, share a library. Each app has
the library spliced in at `c/`. A monorepo brings all of them together:
the apps at `a/` and `b/`, and the library once more at `c/`, to work on
it directly.

```text
   monorepo
    /  |  \
  a/   |   b/
    \  |  /
      c/
```

That's a *diamond*: two paths lead from the monorepo to the library, one
through each app. A monorepo without splices would keep the library once
and let `a/c/` and `b/c/` be symlinks to `../c/`. But then the app on
its own, cloned from its own repository, has a link that points outside
of it. With splices, each copy is real: the app's repository has the
library's files, and `c/.splice` says where they come from. The monorepo
has the library three times, and keeps the copies in sync by pulling and
pushing, as below.

- **Library** (`$UPSTREAM`, reached as `https://git.example.com/c.git`):
  `c seed`.
- **Apps** (`$UPSTREAM-a`, `$UPSTREAM-b`, reached as
  `https://git.example.com/a.git` and `b.git`): a seed commit each, then
  `add c`, which spliced the library in at `c/`.
- **Monorepo**: one commit, no splice yet.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../scenarios/readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_diamond
```

### The monorepo brings them together

```scrut
$ git splice clone https://git.example.com/a.git a
===  a: fetching https://git.example.com/a.git
ok   a: cloned 6962bd0 from main
```

```scrut
$ git splice clone https://git.example.com/b.git b
===  b: fetching https://git.example.com/b.git
ok   b: cloned 8333d5f from main
```

```scrut
$ git splice clone https://git.example.com/c.git c
===  c: fetching https://git.example.com/c.git
ok   c: cloned 0bfc154 from main
```

The apps' `c/.splice` came along, so the monorepo has five splices,
three of them of the library:

```scrut
$ git splice status
On branch main

  up to date  a
  up to date  a/c
  up to date  b
  up to date  b/c
  up to date  c
```

Each is a splice of its own, with its own id: each app ran `clone` for
the library, and so did the monorepo
([splice identity](../splice-identity/README.md)). All three share the
library's upstream, and with it one key and one fetch
([upstreams](../upstreams/README.md)):

```scrut
$ git grep 'id = ' -- '*/.splice' | tr '\t' ' '
a/.splice: id = dc1f63e7168fb5f0
a/c/.splice: id = f73be57fd033f814
b/.splice: id = a74f3d3a6a024a89
b/c/.splice: id = 7d96e5d8a73e4c4b
c/.splice: id = 27a7630097a94256
```

By their ids, the three copies of the library are independent splices
([splice identity](../splice-identity/README.md#what-an-id-is)): each
repository cloned the library itself. They're one library, at possibly
different versions, as in a package manager's diamond: one app may still
use an older version than the other. Keeping them at the same version is
up to the monorepo, where that's wanted.

```scrut
$ git splice key a/c
c
```

```scrut
$ git splice key b/c
c
```

```scrut
$ git splice key c
c
```

The copies cost little in the repository. Git stores a file by its
content, so the three `file.txt` are one object. Only the `.splice`
files differ, in their ids:

```scrut
$ git ls-tree -r --abbrev=7 --format='%(objectname) %(path)' HEAD -- c a/c b/c
10b4956 a/c/.splice
3436b98 a/c/file.txt
cb3b983 b/c/.splice
3436b98 b/c/file.txt
b6f8f56 c/.splice
3436b98 c/file.txt
```

The checkout does have three copies of each file. A change to one copy
reaches the others only by a push and their pulls, as below.

### A change to the library, round trip

The change is made once, in the monorepo's `c/`, and goes to the
library's upstream:

```scrut
$ echo "c fix" >>c/file.txt && git commit -q -a -m "c fix"
```

```scrut
$ git splice push c
ok   c: pushed 2f685c3 to main
```

Now `a/c/` and `b/c/` are behind the library's upstream:

```scrut
$ git splice status
On branch main

  behind 1    a/c
  behind 1    b/c

  up to date  a
  up to date  b
  up to date  c
```

In terms of the [sync model](../sync-model/README.md): R of `c/`, the
commit its push sent, is the library's upstream branch T now. `a/c/` and
`b/c/` still have the old content, so their R is the old commit.
`log --graph` leaves out `c/`, which is up to date:

```scrut
$ git splice log --graph c a/c b/c
===  a/c (main)
> 2f685c3 (T) c fix  (Test <test@example.com>)
o 0bfc154 (R) c seed  (Test <test@example.com>)
===  b/c (main)
> 2f685c3 (T) c fix  (Test <test@example.com>)
o 0bfc154 (R) c seed  (Test <test@example.com>)
```

The copies of the library differ now: they're at different versions.
`status` shows it only indirectly, as two splices behind their upstream.
Comparing the folders, without `.splice`, shows it directly:

```scrut
$ git diff --stat HEAD:c HEAD:a/c -- ':!.splice'
 file.txt | 1 -
 1 file changed, 1 deletion(-)
```

Each pulls it in, and `a/` and `b/` are then ahead of their upstreams,
by the new `c/` content and `c/.splice`:

```scrut
$ git splice pull a/c b/c
ok   a/c fetched
ok   b/c fetched
ok   a/c: pulled 2f685c3
ok   b/c: pulled 2f685c3
```

```scrut
$ git splice status
On branch main

  ahead 1     a
  ahead 1     b

  up to date  a/c
  up to date  b/c
  up to date  c
```

```scrut
$ git splice push a b
ok   a: pushed 7f874c1 to main
ok   b: pushed e9b20a7 to main
```

A clone of one app on its own, e.g. by an outside contributor, has the
library's new version, as plain files, with the `.splice` that lets
`git-splice` sync it from there:

```scrut
$ git clone -q "$UPSTREAM-a" ../a-standalone && ls -A ../a-standalone/c
.splice
file.txt
```

```scrut
$ cat ../a-standalone/c/file.txt
c seed
c fix
```

After the round trip, the three copies have the same files and every
splice is up to date. Their synced commits differ, though: `c/` pushed
the change and didn't pull it, and a push doesn't move U(H):

```scrut
$ git grep 'commit = ' -- c/.splice a/c/.splice b/c/.splice | tr '\t' ' '
a/c/.splice: commit = 2f685c31331f50c0186c1d8a91e398f13f179d83
b/c/.splice: commit = 2f685c31331f50c0186c1d8a91e398f13f179d83
c/.splice: commit = 0bfc154c1c749180f5927393b915bfb27ad635fd
```

So different synced commits don't mean different versions. Different
files do, and the three copies have the same:

```scrut
$ git diff --quiet HEAD:c HEAD:a/c -- ':!.splice' &&
>   git diff --quiet HEAD:c HEAD:b/c -- ':!.splice' &&
>   echo "the same files"
the same files
```

`git-splice` compares each copy only with its own upstream, not the
copies with each other. Copies with one id,
[mirrors](../../../docs/going-forward/mirrors.md), are meant to stay
alike; these three aren't.
