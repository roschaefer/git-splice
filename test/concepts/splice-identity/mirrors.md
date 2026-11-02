# Mirrors

Two folders with the same [id](README.md) are mirrors, meant to have the
same files. Here `vendor/a/` gets a mirror, and `third_party/a/`, cloned
from the same upstream, stays independent.
[What mirrors would need](../../../docs/going-forward/mirrors.md) from
`git-splice` is a separate page.

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../scenarios/readme-setup.sh"
```

```scrut
$ build_scenario scenario_splice_identity
```
-->

```scrut
$ git splice clone https://git.example.com/a.git vendor/a
===  vendor/a: fetching https://git.example.com/a.git
ok   vendor/a: cloned bde4164 from main
```

```scrut
$ git splice clone https://git.example.com/a.git third_party/a
===  third_party/a: fetching https://git.example.com/a.git
ok   third_party/a: cloned bde4164 from main
```

## A copy shares the id

A plain copy takes `.splice` along:

```scrut
$ cp -r vendor/a vendor/a-copy &&
>   git add vendor/a-copy &&
>   git commit -q -m "copy vendor/a"
```

```scrut
$ git grep 'id = ' -- '*/.splice' | tr '\t' ' '
third_party/a/.splice: id = 9cbe29027f507b0e
vendor/a-copy/.splice: id = 224f2c2563d3b6f7
vendor/a/.splice: id = 224f2c2563d3b6f7
```

That makes `vendor/a-copy/` a mirror of `vendor/a/`. If the copy should go
its own way, use `git splice clone` instead: same files, same synced
commit, its own id.

Don't point a copy at a fork by changing its URL. It keeps the id, so it
still declares a mirror, and nothing warns about it. Instead,
[add the fork as an upstream](../upstreams/README.md#a-fork-and-the-original)
of the one splice.

Commands work on a path and never compare ids across paths, so each
mirror is pulled and pushed on its own:

```scrut
$ git splice status
On branch main

  up to date  third_party/a
  up to date  vendor/a-copy
  up to date  vendor/a
```

You can also get the same id twice without copying anything: when two
upstreams contain the same nested splice, both bring its `.splice` into
the monorepo. Two upstreams that each cloned the library themselves give
it two ids, as in the [diamond](../nesting/diamond.md).

## A mirror drifts

Nothing keeps mirrors alike. The upstream moves on, and only `vendor/a/`
is pulled:

```scrut
$ seed_bare_repo "$UPSTREAM" "upstream change"
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (main moved bde4164..6045a98)
ok   vendor/a: pulled 6045a98
```

```scrut
$ git splice status
On branch main

  behind 1    third_party/a
  behind 1    vendor/a-copy

  up to date  vendor/a
```

`status` says `vendor/a-copy/` is behind, the same as for `third_party/a/`,
which may stay behind. To see drift, compare the folders in `HEAD` without
their `.splice`:

```scrut
$ git diff --stat HEAD:vendor/a HEAD:vendor/a-copy -- ':!.splice'
 file.txt | 1 -
 1 file changed, 1 deletion(-)
```

Pulling the copy resolves it:

```scrut
$ git splice pull vendor/a-copy
ok   vendor/a-copy fetched
ok   vendor/a-copy: pulled 6045a98
```

```scrut
$ git diff --quiet HEAD:vendor/a HEAD:vendor/a-copy -- ':!.splice' && echo "mirrors"
mirrors
```

Only the files count. A push doesn't move U(H), so a mirror that pushed a
change has an older U(H) than one that pulled it, with the same files
([diamond](../nesting/diamond.md)).

## Mirrors that swap paths

Mirrors are one splice, so the rebuild can't tell them apart. Unlike
[independent splices](../../scenarios/07-moved-folders/02-swapped-splices/README.md),
each path keeps its own history, whichever mirror's files it has now. A commit in each mirror, not pushed yet:

```scrut
$ echo "not for upstream" >vendor/a/secret.txt &&
>   git add vendor/a &&
>   git commit -q -m "a secret"
```

```scrut
$ echo "copy change" >>vendor/a-copy/file.txt && git commit -q -am "copy change"
```

Then they swap paths:

```scrut
$ git mv vendor/a tmp &&
>   git mv vendor/a-copy vendor/a &&
>   git mv tmp vendor/a-copy &&
>   git commit -q -m "swap the mirrors"
```

`vendor/a/` no longer has the secret, but a push still sends `a secret`,
then the swap that removes it:

```scrut
$ git splice log vendor/a
===  vendor/a (main)
< c5e6540 swap the mirrors  (Test <test@example.com>)
< 920226f a secret  (Test <test@example.com>)
```

Nothing in the monorepo tells this swap apart from edits that make one
splice look like the other
([#193](https://github.com/roschaefer/git-splice/issues/193)). To avoid
it, keep mirrors alike: push one, and pull the others right away
([mirrors](../../../docs/going-forward/mirrors.md#meanwhile-discipline)).

## Which mirror a move came from

Once two folders have one id, the id alone can't say where a move came
from. A commit that adds `c/` and removes both `a/` and `b/`, which had
the same id, is a move from the one with more unchanged files. On a tie,
`libs/a/` comes from `vendor/a/`, the folder with its name. Without one,
it's no move, and the splice's history starts there.
