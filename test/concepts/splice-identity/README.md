# Splice identity

What a splice's `id` names, what it's for, and why two folders may have
the same one.

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
| a new URL, or another upstream | stays: a fork or a mirror is meant to be a copy |
| `cp -r` of the folder, or a nested `.splice` reaching the monorepo twice | is copied: now two folders have it |

A splice keeps its id however its folder or its upstream changes. The
id is derived from the path and `HEAD` when the splice is made, not
random, so the same command on the same commit writes the same file
([the design](../../../docs/design/README.md#the-splice-file)).

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
 commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
 id = 25e766b33a0eb239
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
libs/a/.splice: id = 08502bf01cd0c0a3
vendor/a/.splice: id = 25e766b33a0eb239
```

What the two have in common is their upstream: they share its fetched
refs, and they drift apart when only one of them is pulled
([upstreams](../upstreams/README.md)).

### A move keeps the id

```scrut
$ mkdir third_party && git mv libs/a third_party/a && git commit -q -m "move libs/a"
```

```scrut
$ git grep 'id = ' -- '*/.splice' | tr '\t' ' '
third_party/a/.splice: id = 08502bf01cd0c0a3
vendor/a/.splice: id = 25e766b33a0eb239
```

Today the rebuild compares ids only at one path, between a commit and its
parent: where the `.splice` there is new, or has another id, this
splice's history starts, its mount. That's what keeps two splices that
swap paths apart ([swapped-splices](../../scenarios/swapped-splices/README.md)). It
doesn't follow a splice back to its old path yet, so unpushed commits are
folded into the move
([#4](https://github.com/roschaefer/git-splice/issues/4)).

The id alone couldn't say where a splice came from either, once two
folders have it, as in the next section. A commit that adds `c/` and
removes `a/` is a move from `a/`, even if `b/` has the same id. One
that adds `c/` and removes both `a/` and `b/` is ambiguous, as Git's own
rename detection is with two identical files.

### A copy shares the id

A plain copy, e.g. to give a second app its own copy of the library,
copies `.splice` too:

```scrut
$ cp -r vendor/a vendor/a-copy && git add vendor/a-copy && git commit -q -m "copy vendor/a"
```

```scrut
$ git grep 'id = ' -- '*/.splice' | tr '\t' ' '
third_party/a/.splice: id = 08502bf01cd0c0a3
vendor/a-copy/.splice: id = 25e766b33a0eb239
vendor/a/.splice: id = 25e766b33a0eb239
```

That's allowed. Every command works on a splice by its path, and nothing
compares ids across paths. Both are splices of their own, and the copy's
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

### Same id, different synced commits

Two folders with the same id can be at different synced commits U.
Nothing ties them together after the copy. What it means depends on
their upstreams.

**Same upstream: drift.** The upstream moves on, and only `vendor/a` is
pulled:

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
vendor/a-copy/.splice: commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
vendor/a-copy/.splice: id = 25e766b33a0eb239
vendor/a/.splice: commit = 6045a986b5afb475cd0af0caf6bb622db918a25b
vendor/a/.splice: id = 25e766b33a0eb239
```

```scrut
$ git splice status
ok   third_party/a -> main (pull: behind 1)
ok   vendor/a-copy -> main (pull: behind 1)
ok   vendor/a -> main (up to date)
```

`vendor/a-copy` lags behind just as `third_party/a` does, which has an id
of its own. So drift is about the upstream, not the id, and it may be
wanted for a while, e.g. while one app tries the new version first.
Different synced commits aren't always drift, though: a push doesn't move
U ([upstreams](../upstreams/README.md#drift)).

**Another upstream: a fork.** A copy whose URL is changed to a fork's
vendors the fork next to the original:

```scrut
$ cp -r vendor/a-copy vendor/a-fork && git config --file vendor/a-fork/.splice upstream.origin.url https://git.example.com/a-fork.git && git add vendor/a-fork && git commit -q -m "vendor a fork"
```

```scrut
$ git splice pull vendor/a-fork
ok   vendor/a-fork fetched
ok   vendor/a-fork: pulled c09993d
```

```scrut
$ git grep -e 'id = ' -e 'commit = ' -e 'url = ' -- vendor/a-copy/.splice vendor/a-fork/.splice | tr '\t' ' '
vendor/a-copy/.splice: commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
vendor/a-copy/.splice: id = 25e766b33a0eb239
vendor/a-copy/.splice: url = https://git.example.com/a.git
vendor/a-fork/.splice: commit = c09993d6070910488d3e924b417023fccf6f305a
vendor/a-fork/.splice: id = 25e766b33a0eb239
vendor/a-fork/.splice: url = https://git.example.com/a-fork.git
```

Here the different synced commits are the point, not drift. The id can't
tell this case from an upstream that moved to a new URL, since both keep
it. `git splice clone https://git.example.com/a-fork.git vendor/a-fork`
would have given the fork an id of its own.

### Where the id must not repeat

A splice can't be inside itself: a `.splice` with the same id as one
above it means an upstream splices in, directly or not, something that
contains it. Every pull then nests one more copy
([cycle](../nesting/cycle.md)). Nothing refuses it yet
([#86](https://github.com/roschaefer/git-splice/issues/86)).
