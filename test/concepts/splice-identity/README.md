# Splice identity

What a splice's `id` names, what it's for, and what it means when two
folders have the same one: they're meant to be mirrors.

- **Upstream** (`$UPSTREAM`, reached as `https://git.example.com/a.git`):
  `seed`.
- **A fork of it** (`$UPSTREAM-fork`, reached as
  `https://git.example.com/a-fork.git`): `seed`, then `fork fix`.
- **Monorepo**: one commit, no splice yet.

## What an id is

`clone` and `init` write an `id` into the `.splice` they create. The id
names that **mount**, the act of making this folder a splice of an
upstream. It names neither a folder nor an upstream:

| What happens | The id |
|---|---|
| `clone` or `init` | is new, even for an upstream another folder already splices |
| `git mv` of the folder | moves along with `.splice` |
| a new URL, or another upstream | stays: the upstream moved, or got a second home |
| `cp -r` of the folder, or a nested `.splice` reaching the monorepo twice | is copied: now two folders have it |

A splice keeps its id however its folder or its upstream changes. The
id is derived from the path, `HEAD`, the upstream's URL and the commit
spliced in when the splice is made, not random, so the same command on
the same commit writes the same file
([the design](../../../docs/design/README.md#the-splice-file)).

So the id says which folders are meant to stay alike:

| | Different ids | The same id |
|---|---|---|
| Meaning | **independent** splices, even of one upstream, e.g. a library at two versions | one splice in two places: **mirrors**, meant to have the same files |
| Different content | fine | **drift**, to resolve |
| Made by | `clone` or `init` | a copy, or one nested splice reached twice |

Mirrors can't be enforced, only reported, and git splice doesn't report
them yet: [mirrors](../../../docs/going-forward/mirrors.md) explains why,
and what you can do meanwhile.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../scenarios/readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_splice_identity
```

### Each `clone` is a new splice

```scrut
$ git splice clone https://git.example.com/a.git vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned bde4164 from main
```

```scrut
$ cat vendor/a/.splice | tr '\t' ' '
[splice]
 id = 224f2c2563d3b6f7
 commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
[upstream "origin"]
 url = https://git.example.com/a.git
```

A second clone of the same upstream, at the same commit, is another
splice, with another id:

```scrut
$ git splice clone https://git.example.com/a.git libs/a
===  libs/a: fetching https://git.example.com/a.git
ok   libs/a: cloned bde4164 from main
```

```scrut
$ git grep 'id = ' -- '*/.splice' | tr '\t' ' '
libs/a/.splice: id = a841bb3c200928e9
vendor/a/.splice: id = 224f2c2563d3b6f7
```

What the two have in common is their upstream: they share its fetched
refs, and they end up at different versions when only one of them is
pulled
([upstreams](../upstreams/README.md)).

### A move keeps the id

```scrut
$ mkdir third_party && git mv libs/a third_party/a && git commit -q -m "move libs/a"
```

```scrut
$ git grep 'id = ' -- '*/.splice' | tr '\t' ' '
third_party/a/.splice: id = a841bb3c200928e9
vendor/a/.splice: id = 224f2c2563d3b6f7
```

The rebuild follows a move back to the old path, so the commits from
before it that weren't pushed yet are kept
([moved-with-unpushed-commits](../../scenarios/up-to-date/push-ahead/moved-with-unpushed-commits/README.md)).
It finds the old path by the folder's files: a commit that creates the
folder, and removes one with files of the same names, moved it. The id
then confirms that it's the same splice. Where a `.splice` is new at a
path, without such a move, or has another id, the splice's history
starts: its mount. That's what keeps two splices that swap paths apart
([swapped-splices](../../scenarios/swapped-splices/README.md)).

The id alone couldn't say where a splice came from, once two folders
have it, as in the next section. A commit that adds `c/` and removes
`a/` is a move from `a/`, even if `b/` has the same id. One that adds
`c/` and removes both `a/` and `b/` is a move from the one with more
unchanged files, and a tie is no move, as with Git's own rename
detection and two identical files.

### A copy shares the id

A plain copy, e.g. to give a second app its own copy of the library,
copies `.splice` too:

```scrut
$ cp -r vendor/a vendor/a-copy && git add vendor/a-copy && git commit -q -m "copy vendor/a"
```

```scrut
$ git grep 'id = ' -- '*/.splice' | tr '\t' ' '
third_party/a/.splice: id = a841bb3c200928e9
vendor/a-copy/.splice: id = 224f2c2563d3b6f7
vendor/a/.splice: id = 224f2c2563d3b6f7
```

The copy declares a **mirror** of `vendor/a`. For a copy that should go
its own way, `git splice clone` gives the same files, at the same synced
commit, with an id of its own. Every command works on a splice by its
path, and nothing compares ids across paths, so each copy is pulled and
pushed on its own. Both are splices of their own, and the copy's
history starts with the copy, its mount:

```scrut
$ git splice status
ok   third_party/a -> main (up to date)
ok   vendor/a-copy -> main (up to date)
ok   vendor/a -> main (up to date)
```

A copy isn't the only way to get the same id twice. If two upstreams
contain the same nested splice, e.g. because one of them splices in the
other, both bring its `.splice` into the monorepo, each in its own
folder. Two upstreams that each cloned the library themselves give it
two ids, as in the [diamond](../nesting/diamond.md).

### A mirror drifts

Nothing keeps mirrors alike: each is pulled on its own. The upstream
moves on, and only `vendor/a` is pulled:

```scrut
$ seed_bare_repo "$UPSTREAM" "upstream change"
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved bde4164..6045a98)
ok   vendor/a: pulled 6045a98
```

```scrut
$ git grep -e 'id = ' -e 'commit = ' -- vendor/a/.splice vendor/a-copy/.splice | tr '\t' ' '
vendor/a-copy/.splice: id = 224f2c2563d3b6f7
vendor/a-copy/.splice: commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
vendor/a/.splice: id = 224f2c2563d3b6f7
vendor/a/.splice: commit = 6045a986b5afb475cd0af0caf6bb622db918a25b
```

```scrut
$ git splice status
ok   third_party/a -> main (pull: behind 1)
ok   vendor/a-copy -> main (pull: behind 1)
ok   vendor/a -> main (up to date)
```

`vendor/a-copy` is meant to mirror `vendor/a`, but has other files now:
it has **drifted**. `status` only says it's behind its upstream, just as
`third_party/a`, which is independent and may stay behind. A report of
mirrors that differ is possible, but not there yet
([mirrors](../../../docs/going-forward/mirrors.md)).

Until then, you can compare mirrors yourself. Their folders, without
`.splice`, should have the same tree, so `git diff` between the two
folders in `HEAD` shows what's different:

```scrut
$ git diff --stat HEAD:vendor/a HEAD:vendor/a-copy -- ':!.splice'
 file.txt | 1 -
 1 file changed, 1 deletion(-)
```

Pulling the copy resolves the drift:

```scrut
$ git splice pull vendor/a-copy
ok   vendor/a-copy fetched
ok   vendor/a-copy: pulled 6045a98
```

```scrut
$ git diff --quiet HEAD:vendor/a HEAD:vendor/a-copy -- ':!.splice' && echo "mirrors"
mirrors
```

Different synced commits alone aren't drift: a push doesn't move U, so
a mirror that pushed a change has an older U than one that pulled it,
with the same files ([diamond](../nesting/diamond.md)).

### Mirrors that swap paths

Mirrors are one splice, so the rebuild can't tell them apart either.
Two splices that swap paths each start a new history with the swap
([swapped-splices](../../scenarios/swapped-splices/README.md)); two
mirrors don't. Each path keeps its own history, whichever mirror's files
it has now.

A commit in each mirror, not pushed yet:

```scrut
$ echo "not for upstream" >vendor/a/secret.txt && git add vendor/a && git commit -q -m "a secret"
```

```scrut
$ echo "copy change" >>vendor/a-copy/file.txt && git commit -q -am "copy change"
```

Then they swap paths:

```scrut
$ git mv vendor/a tmp && git mv vendor/a-copy vendor/a && git mv tmp vendor/a-copy && git commit -q -m "swap the mirrors"
```

`vendor/a` has the copy's files now, without the secret. But its history
is still the one of the path: a push sends `a secret`, then the swap,
which removes it again and brings in the copy's change.

```scrut
$ git splice log vendor/a
===  vendor/a (main)
< c5e6540 swap the mirrors  (Test <test@example.com>)
< 920226f a secret  (Test <test@example.com>)
```

Nothing in the monorepo tells this swap apart from edits to one splice
that make its files look like the other mirror's. Keeping mirrors alike
avoids it: push one, and pull the others right away
([mirrors](../../../docs/going-forward/mirrors.md#meanwhile-discipline)).

### A fork is a splice of its own

To vendor a fork next to the original, clone it:

```scrut
$ git splice clone https://git.example.com/a-fork.git vendor/a-fork
===  vendor/a-fork: fetching https://git.example.com/a-fork.git
ok   vendor/a-fork: cloned c09993d from main
```

```scrut
$ git grep -e 'id = ' -e 'url = ' -- vendor/a/.splice vendor/a-fork/.splice | tr '\t' ' '
vendor/a-fork/.splice: id = c9c8218874380302
vendor/a-fork/.splice: url = https://git.example.com/a-fork.git
vendor/a/.splice: id = 224f2c2563d3b6f7
vendor/a/.splice: url = https://git.example.com/a.git
```

A copy of `vendor/a` whose URL is changed to the fork's would keep the
id, and so declare a mirror of something that isn't one. The id can't
tell that from an upstream that moved to a new URL, which keeps it on
purpose, and nothing warns about it yet.

### Where the id must not repeat

A splice can't be inside itself: a `.splice` with the same id as one
above it means an upstream splices in, directly or not, something that
contains it. Every pull then nests one more copy
([cycle](../nesting/cycle.md)). Nothing refuses it yet
([#86](https://github.com/roschaefer/git-splice/issues/86)).
