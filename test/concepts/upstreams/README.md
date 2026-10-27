# Upstreams

An upstream is much like a Git remote: a named repository a splice fetches
from and pushes to. Its name and URL live in `.splice`:

```text
[upstream "origin"]
	url = https://git.example.com/s.git
```

Unlike a Git remote, it is fetched into private refs without creating an
entry under `git remote`. A splice can name several upstreams, such as a
fork and the original; `default-upstream` selects one unless a command
uses `--upstream`
([example](../../scenarios/04-upstreams/02-several-upstreams/README.md)).

## URLs, keys and refs

Each named upstream in `.splice` has a URL. The monorepo uses that URL as
the upstream's identity.

A *key* is a short, ref-friendly nickname for one unique upstream URL. The
mapping is one-to-one within the monorepo: one URL has one key, and one key
names one URL. This turns URLs containing `/`, `:`, `@` and other awkward
characters into refs such as `refs/splices/s/heads/main`.

The first fetch records the mapping and fetches the upstream's branches to
`refs/splices/<key>/heads/`. These are ordinary Git refs, so commands such
as `git log` can read them and `git worktree add` can check them out
([example](../../walkthrough/fetch.md#looking-at-an-upstream)).

Splices that name the same URL share its key and fetched refs. Their
`.splice` files, IDs and synced commits remain independent.

## The same library at different versions

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../scenarios/readme-setup.sh"
```

```scrut
$ build_scenario scenario_upstreams
```

```scrut
$ git splice clone https://git.example.com/s.git app-a/s >/dev/null &&
>   git splice clone https://git.example.com/s.git app-b/s >/dev/null
```
-->

In this example, `app-a/` and `app-b/` each contain their own splice of
the library `s`. Both `.splice` files name the same upstream URL:

```scrut
$ git config --file app-a/s/.splice upstream.origin.url
https://git.example.com/s.git
```

```scrut
$ git config --file app-b/s/.splice upstream.origin.url
https://git.example.com/s.git
```

The URL therefore resolves to the same key from either splice:

```scrut
$ git splice key app-a/s
s
```

```scrut
$ git splice key app-b/s
s
```

There is only one fetched `main` ref for that key:

```scrut
$ git for-each-ref --format='%(objectname:short) %(refname)' refs/splices
bde4164 refs/splices/s/heads/main
```

They still choose versions independently. Pulling a new upstream commit
into `app-a/s` leaves `app-b/s` behind:

```scrut
$ seed_bare_repo "$UPSTREAM" "upstream change" &&
>   git splice pull app-a/s >/dev/null &&
>   git splice status
On branch main

  behind 1    app-b/s

  up to date  app-a/s
```

The two folders are independent splices because they have different
[`id`s](../splice-identity/README.md). Sharing an upstream does not make
them mirrors.

## Using a mirror

URLs are compared as written. A mirror is another upstream, even when its
URL reaches the same repository:

```scrut
$ git splice clone https://mirror.example.com/s.git app-c/s >/dev/null &&
>   git splice key app-c/s
mirror.example.com-s
```

```scrut
$ git config --get-regexp '^splice\.'
splice.s.url https://git.example.com/s.git
splice.mirror.example.com-s.url https://mirror.example.com/s.git
```

Each URL gets its own key and fetched refs. To use both for one splice,
name both as upstreams in its `.splice` file. A fork is a separate
repository rather than another URL for the same one, but it is likewise a
separate upstream.
