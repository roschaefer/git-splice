# Upstreams

What a splice's upstream is, how it relates to the refs under
`refs/splices/<key>/`, and what it means when two splices of one
upstream are at different versions.

- **Upstream** (`$UPSTREAM`): `seed`. The monorepo reaches it as
  `https://git.example.com/s.git`, and as
  `https://mirror.example.com/s.git` too.
- **Monorepo**: one commit, no splice yet.

## What an upstream is

A splice's `.splice` names its upstream like a Git remote:
`[upstream "origin"]` with a `url`. Exactly one upstream per splice is
supported for now. The name is there so that a splice can later sync
with more than one, e.g. a company fork and the original. The synced
commit U stays one per splice: a sync point is a commit, whichever
upstream it came from.

The monorepo knows an upstream by its URL. The first command that
fetches it gives it a **key**, a short name recorded in the repository's
config, and fetches its branches to `refs/splices/<key>/`. So:

| | is one per |
|---|---|
| `.splice`, `id`, synced commit U | splice |
| key, `refs/splices/<key>/*`, fetch | upstream URL, shared by every splice that names it |

[splice-refs](../../scenarios/splice-refs/README.md) shows what each command does to
those refs, and [splice-identity](../splice-identity/README.md) what
the `id` names.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../scenarios/readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_upstreams
```

### Two splices, one upstream

Two apps each get their own copy of a shared library, s. Each `clone` is
a splice of its own. (It would be the same if each app were a splice
with s nested in it, as in
[nested-splices](../../scenarios/nested-splices/README.md).)

```scrut
$ git splice clone https://git.example.com/s.git app-a/s
===  app-a/s: fetching https://git.example.com/s.git
ok   app-a/s: cloned bde4164 from main
```

```scrut
$ git splice clone https://git.example.com/s.git app-b/s
===  app-b/s: fetching https://git.example.com/s.git
ok   app-b/s: cloned bde4164 from main
```

```scrut
$ cat app-a/s/.splice | tr '\t' ' '
[splice]
 commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
 id = e55ed235e80a83a7
[upstream "origin"]
 url = https://git.example.com/s.git
```

The upstream has one key, and one set of refs:

```scrut
$ git config --get-regexp '^splice\.'
splice.s.url https://git.example.com/s.git
```

```scrut
$ git splice key app-a/s && git splice key app-b/s
s
s
```

```scrut
$ git for-each-ref --format='%(objectname:short) %(refname)' refs/splices
bde4164 refs/splices/s/main
```

`fetch` fetches each upstream once, and reports for every splice of it:

```scrut
$ seed_bare_repo "$UPSTREAM" "upstream change"
```

```scrut
$ git splice fetch
ok   app-a/s fetched (main moved bde4164..6045a98)
ok   app-b/s fetched (main moved bde4164..6045a98)
```

### One library at two versions

Only app a pulls the new version:

```scrut
$ git splice pull app-a/s
ok   app-a/s fetched
ok   app-a/s: pulled 6045a98
```

```scrut
$ git splice status
ok   app-a/s -> main (up to date)
ok   app-b/s -> main (pull: behind 1)
```

```scrut
$ git grep 'commit = ' -- '*/.splice' | tr '\t' ' '
app-a/s/.splice: commit = 6045a986b5afb475cd0af0caf6bb622db918a25b
app-b/s/.splice: commit = bde416459fbcc09c9b585f3b65a94cab3f68bfcd
```

`app-a/s` and `app-b/s` were cloned separately, so they have different
ids: they're **independent**
([splice identity](../splice-identity/README.md#what-an-id-is)). That
they're at different versions is fine, e.g. while app a tries the new
one first, and `status` reports app b's only as behind its upstream. If
both apps should always share one version, the two need to be mirrors,
with the same id. Then a difference is **drift**, which git splice
doesn't report yet ([mirrors](../../../docs/going-forward/mirrors.md)).

Whether two splices differ is a matter of their files, or R in the
[sync model](../sync-model/README.md), not of their synced commits U. A
push doesn't move U, so a splice that pushed a change is at an older U
than a copy that pulled it, with the same files
([diamond](../nesting/diamond.md)).

### One repository, two URLs

A URL is what the monorepo compares, not the repository behind it. The
same repository under another URL, e.g. a mirror, or SSH instead of
HTTPS, is another upstream to the monorepo, with a key and refs of its
own:

```scrut
$ git splice clone https://mirror.example.com/s.git app-c/s
===  app-c/s: fetching https://mirror.example.com/s.git
ok   app-c/s: cloned 6045a98 from main
```

```scrut
$ git config --get-regexp '^splice\.'
splice.s.url https://git.example.com/s.git
splice.mirror.example.com-s.url https://mirror.example.com/s.git
```

```scrut
$ git splice key app-c/s
mirror.example.com-s
```

So comparing URLs couldn't tell that `app-c/s` splices the same
repository as the others. With several upstreams per splice, a splice
that names both URLs would tell the monorepo that they are copies of
each other.

How this compares with a package manager's names, versions and lockfile:
[package managers](../../../docs/going-forward/package-managers.md).
