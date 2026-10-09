# Diamond

Two apps, A and B, each in a repository of its own, share a library S.
Each app has S spliced in at `s/`. A monorepo M brings all of them
together: A, B, and S once more at the top, to work on it directly.

```text
      M
     /|\
    A | B
     \|/
      S
```

That's a **diamond**: two paths lead from M to S, one through A and one
through B. A monorepo without splices would keep S once and let `a/s` and
`b/s` be symlinks to `../s`. But then A on its own, cloned from its own
repository, has a link that points outside of it. With splices, each copy
is real: A's repository has S's files, and `s/.splice` says where they
come from. M has S three times, and keeps the copies in sync by pulling
and pushing, as below.

- **S** (`$UPSTREAM`, reached as `https://git.example.com/s.git`):
  `s seed`.
- **A** and **B** (`$UPSTREAM-a`, `$UPSTREAM-b`, reached as
  `https://git.example.com/a.git` and `b.git`): a seed commit each, then
  `add s`, which spliced S in at `s/`.
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

### M brings A, B and S together

```scrut
$ git splice clone https://git.example.com/a.git a && git splice clone https://git.example.com/b.git b && git splice clone https://git.example.com/s.git s
===  a: fetching https://git.example.com/a.git
ok   a: cloned d8c030f from main
===  b: fetching https://git.example.com/b.git
ok   b: cloned e8f5762 from main
===  s: fetching https://git.example.com/s.git
ok   s: cloned 1917a62 from main
```

A's and B's `s/.splice` came along, so M has five splices, three of
them of S:

```scrut
$ git splice status
ok   a -> main (up to date)
ok   a/s -> main (up to date)
ok   b -> main (up to date)
ok   b/s -> main (up to date)
ok   s -> main (up to date)
```

Each is a splice of its own, with its own id: A and B each ran `clone`
for S, and so did M ([splice identity](../splice-identity/README.md)).
All three share S's upstream, and with it one key and one fetch
([upstreams](../upstreams/README.md)):

```scrut
$ git grep 'id = ' -- '*/.splice' | tr '\t' ' '
a/.splice: id = ada385bc3fe39937
a/s/.splice: id = 2207a2e3260b644a
b/.splice: id = 40ff492029bce288
b/s/.splice: id = 2b29a3b662c7595b
s/.splice: id = b34eca1503aaac78
```

By their ids, the three copies of S are independent splices
([splice identity](../splice-identity/README.md#what-an-id-is)): each
repository cloned S itself. They're one library, at possibly different
versions, as in a package manager's diamond: A may still use an older S
than B. Keeping them at the same version is up to the monorepo, where
that's wanted.

```scrut
$ git splice key a/s && git splice key b/s && git splice key s
s
s
s
```

The copies cost little in the repository. Git stores a file by its
content, so the three `file.txt` are one object. Only the `.splice`
files differ, in their ids:

```scrut
$ git ls-tree -r --abbrev=7 --format='%(objectname) %(path)' HEAD -- s a/s b/s
0803847 a/s/.splice
afc5fd8 a/s/file.txt
65cd514 b/s/.splice
afc5fd8 b/s/file.txt
df06afb s/.splice
afc5fd8 s/file.txt
```

The checkout does have three copies of each file, and a change to S
shows up in each of them.

### A change to S, round trip

The change is made once, in M's `s/`, and goes to S's upstream:

```scrut
$ echo "s fix" >>s/file.txt && git commit -q -a -m "s fix"
```

```scrut
$ git splice push s
ok   s: pushed 9854a3b to main
```

Now `a/s` and `b/s` are behind S's upstream:

```scrut
$ git splice status
ok   a -> main (up to date)
ok   a/s -> main (pull: behind 1)
ok   b -> main (up to date)
ok   b/s -> main (pull: behind 1)
ok   s -> main (up to date)
```

In terms of the [sync model](../sync-model/README.md): `s`'s R, the
commit its push sent, is S's upstream branch T now. `a/s` and `b/s`
still have the old content, so their R is the old commit. `log --graph`
leaves out `s`, which is up to date:

```scrut
$ git splice log --graph s a/s b/s
===  a/s (main)
> 9854a3b (T) s fix  (Test <test@example.com>)
o 1917a62 (R) s seed  (Test <test@example.com>)
===  b/s (main)
> 9854a3b (T) s fix  (Test <test@example.com>)
o 1917a62 (R) s seed  (Test <test@example.com>)
```

The copies of S differ now: they're at different versions of S.
`status` shows it only indirectly, as two splices behind their
upstream. Comparing the folders, without `.splice`, shows it directly:

```scrut
$ git diff --stat HEAD:s HEAD:a/s -- ':!.splice'
 file.txt | 1 -
 1 file changed, 1 deletion(-)
```

Each pulls it in, and A and B are then ahead of their upstreams, by the
new `s/` content and `s/.splice`:

```scrut
$ git splice pull a/s b/s
ok   a/s fetched
ok   b/s fetched
ok   a/s: pulled 9854a3b
ok   b/s: pulled 9854a3b
```

```scrut
$ git splice status
ok   a -> main (push: ahead 1)
ok   a/s -> main (up to date)
ok   b -> main (push: ahead 1)
ok   b/s -> main (up to date)
ok   s -> main (up to date)
```

```scrut
$ git splice push a b
ok   a: pushed 7b7b00d to main
ok   b: pushed ff1ad96 to main
```

A clone of A on its own, e.g. by an outside contributor, has S's new
version, as plain files, with the `.splice` that lets git splice sync it
from there:

```scrut
$ git clone -q "$UPSTREAM-a" ../a-standalone && ls -A ../a-standalone/s && cat ../a-standalone/s/file.txt
.splice
file.txt
s seed
s fix
```

After the round trip, the three copies have the same files and every
splice is up to date. Their synced commits differ, though: `s` pushed
the change and didn't pull it, and a push doesn't move U:

```scrut
$ git grep 'commit = ' -- s/.splice a/s/.splice b/s/.splice | tr '\t' ' '
a/s/.splice: commit = 9854a3b0e01f22a40a9b55704bf2add3185ad502
b/s/.splice: commit = 9854a3b0e01f22a40a9b55704bf2add3185ad502
s/.splice: commit = 1917a62ce23de14693c0d3f5f5025e4e03d1460f
```

So different synced commits don't mean different versions. Different
files do, and the three copies have the same:

```scrut
$ git diff --quiet HEAD:s HEAD:a/s -- ':!.splice' && git diff --quiet HEAD:s HEAD:b/s -- ':!.splice' && echo "the same files"
the same files
```

git splice compares each copy only with its own upstream, not the
copies with each other. Copies with one id,
[mirrors](../../../docs/going-forward/mirrors.md), are meant to stay
alike; these three aren't.
