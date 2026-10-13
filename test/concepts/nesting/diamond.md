# Diamond

Two apps, A and B, each in a repository of its own, share a library C.
Each app has C spliced in at `c/`. A monorepo M brings all of them
together: A, B, and C once more at the top, to work on it directly.

```text
      M
     /|\
    A | B
     \|/
      C
```

That's a **diamond**: two paths lead from M to C, one through A and one
through B. A monorepo without splices would keep C once and let `a/c/` and
`b/c/` be symlinks to `../c/`. But then A on its own, cloned from its own
repository, has a link that points outside of it. With splices, each copy
is real: A's repository has C's files, and `c/.splice` says where they
come from. M has C three times, and keeps the copies in sync by pulling
and pushing, as below.

- **C** (`$UPSTREAM`, reached as `https://git.example.com/c.git`):
  `c seed`.
- **A** and **B** (`$UPSTREAM-a`, `$UPSTREAM-b`, reached as
  `https://git.example.com/a.git` and `b.git`): a seed commit each, then
  `add c`, which spliced C in at `c/`.
- **M**: one commit, no splice yet.

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

### M brings A, B and C together

```scrut
$ git splice clone https://git.example.com/a.git a && git splice clone https://git.example.com/b.git b && git splice clone https://git.example.com/c.git c
===  a: fetching https://git.example.com/a.git
ok   a: cloned 6962bd0 from main
===  b: fetching https://git.example.com/b.git
ok   b: cloned 8333d5f from main
===  c: fetching https://git.example.com/c.git
ok   c: cloned 0bfc154 from main
```

A's and B's `c/.splice` came along, so M has five splices, three of
them of C:

```scrut
$ git splice status
On branch main

  up to date  a
  up to date  a/c
  up to date  b
  up to date  b/c
  up to date  c
```

Each is a splice of its own, with its own id: A and B each ran `clone`
for C, and so did M ([splice identity](../splice-identity/README.md)).
All three share C's upstream, and with it one key and one fetch
([upstreams](../upstreams/README.md)):

```scrut
$ git grep 'id = ' -- '*/.splice' | tr '\t' ' '
a/.splice: id = dc1f63e7168fb5f0
a/c/.splice: id = f73be57fd033f814
b/.splice: id = a74f3d3a6a024a89
b/c/.splice: id = 7d96e5d8a73e4c4b
c/.splice: id = 27a7630097a94256
```

By their ids, the three copies of C are independent splices
([splice identity](../splice-identity/README.md#what-an-id-is)): each
repository cloned C itself. They're one library, at possibly different
versions, as in a package manager's diamond: A may still use an older C
than B. Keeping them at the same version is up to the monorepo, where
that's wanted.

```scrut
$ git splice key a/c && git splice key b/c && git splice key c
c
c
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

### A change to C, round trip

The change is made once, in M's `c/`, and goes to C's upstream:

```scrut
$ echo "c fix" >>c/file.txt && git commit -q -a -m "c fix"
```

```scrut
$ git splice push c
ok   c: pushed 2f685c3 to main
```

Now `a/c/` and `b/c/` are behind C's upstream:

```scrut
$ git splice status
On branch main

  behind 1    a/c
  behind 1    b/c

  up to date  a
  up to date  b
  up to date  c
```

In terms of the [sync model](../sync-model/README.md): `c/`'s R, the
commit its push sent, is C's upstream branch T now. `a/c/` and `b/c/`
still have the old content, so their R is the old commit. `log --graph`
leaves out `c/`, which is up to date:

```scrut
$ git splice log --graph c a/c b/c
===  a/c (main)
> 2f685c3 (T) c fix  (Test <test@example.com>)
o 0bfc154 (R) c seed  (Test <test@example.com>)
===  b/c (main)
> 2f685c3 (T) c fix  (Test <test@example.com>)
o 0bfc154 (R) c seed  (Test <test@example.com>)
```

The copies of C differ now: they're at different versions of C.
`status` shows it only indirectly, as two splices behind their
upstream. Comparing the folders, without `.splice`, shows it directly:

```scrut
$ git diff --stat HEAD:c HEAD:a/c -- ':!.splice'
 file.txt | 1 -
 1 file changed, 1 deletion(-)
```

Each pulls it in, and A and B are then ahead of their upstreams, by the
new `c/` content and `c/.splice`:

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

A clone of A on its own, e.g. by an outside contributor, has C's new
version, as plain files, with the `.splice` that lets `git-splice` sync it
from there:

```scrut
$ git clone -q "$UPSTREAM-a" ../a-standalone && ls -A ../a-standalone/c && cat ../a-standalone/c/file.txt
.splice
file.txt
c seed
c fix
```

After the round trip, the three copies have the same files and every
splice is up to date. Their synced commits differ, though: `c/` pushed
the change and didn't pull it, and a push doesn't move U:

```scrut
$ git grep 'commit = ' -- c/.splice a/c/.splice b/c/.splice | tr '\t' ' '
a/c/.splice: commit = 2f685c31331f50c0186c1d8a91e398f13f179d83
b/c/.splice: commit = 2f685c31331f50c0186c1d8a91e398f13f179d83
c/.splice: commit = 0bfc154c1c749180f5927393b915bfb27ad635fd
```

So different synced commits don't mean different versions. Different
files do, and the three copies have the same:

```scrut
$ git diff --quiet HEAD:c HEAD:a/c -- ':!.splice' && git diff --quiet HEAD:c HEAD:b/c -- ':!.splice' && echo "the same files"
the same files
```

`git-splice` compares each copy only with its own upstream, not the
copies with each other. Copies with one id,
[mirrors](../../../docs/going-forward/mirrors.md), are meant to stay
alike; these three aren't.
