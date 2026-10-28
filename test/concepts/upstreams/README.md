# Upstreams

An upstream is much like a Git remote: a named repository a splice fetches
from and pushes to. Its name and URL live inside the splice folder, in
`.splice`, so they move and branch with it
([why](../../../docs/design/README.md#principles)):

```text
[upstream "origin"]
	url = https://git.example.com/s.git
```

Unlike a Git remote, it is fetched into private refs without creating an
entry under `git remote`
([why](../../../docs/design/README.md#refs-instead-of-remotes)).

## A fork and the original

A common use for several upstreams is working with a company fork while
still fetching the original:

```text
[splice]
	default-upstream = fork
[upstream "origin"]
	url = https://git.example.com/lib.git
[upstream "fork"]
	url = https://git.example.com/company/lib.git
```

When `.splice` names several upstreams, `default-upstream` says which one
commands use when `--upstream` is omitted. Without it, commands that need
one upstream refuse to guess. In the example above, commands use `fork`
unless `--upstream origin` selects the original; `fetch` fetches both
([example](../../scenarios/04-upstreams/02-several-upstreams/README.md)).

## URLs, keys and refs

Each named upstream in `.splice` has a URL. The monorepo uses that URL as
the upstream's identity.

A *key* is a short, ref-friendly nickname for one unique upstream URL. The
mapping is one-to-one within the monorepo: one URL has one key, and one key
names one URL. For example, `https://github.com/acme/shared-lib.git` gets
the key `shared-lib`, so its `main` branch is fetched to
`refs/splices/shared-lib/heads/main`.

The first fetch records the mapping and fetches the upstream's branches to
`refs/splices/<key>/heads/`. These are ordinary Git refs, so commands such
as `git log` can read them and `git worktree add` can check them out
([example](../../walkthrough/fetch.md#looking-at-an-upstream)).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../scenarios/readme-setup.sh"
```

```scrut
$ build_scenario scenario_upstreams
```
-->

## Choosing a key

The generated key comes from the URL, but it can be renamed. Choose a name
you already associate with the upstream, or one that makes its refs easier
to recognize and type.

[`setup.bash`](setup.bash) builds an example whose generated key is `s`.
Rename it to `shared-lib` through any splice that uses the URL:

```scrut
$ git splice key app-a/s shared-lib
ok   app-a/s: renamed key 's' to 'shared-lib'
```

The refs move with the key:

```scrut
$ git for-each-ref --format='%(objectname:short) %(refname)' refs/splices
bde4164 refs/splices/shared-lib/heads/main
```

Because a key belongs to its URL, the rename applies to every splice that
names that URL.

## The same library at different versions

In the same example, `app-a/` and `app-b/` each contain their own splice
of the library `s`. Both `.splice` files name the same upstream URL:

```scrut
$ git config --file app-a/s/.splice upstream.origin.url
https://git.example.com/s.git
```

```scrut
$ git config --file app-b/s/.splice upstream.origin.url
https://git.example.com/s.git
```

Both therefore report the key chosen above:

```scrut
$ git splice key app-a/s
shared-lib
```

```scrut
$ git splice key app-b/s
shared-lib
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
[`id`s](../splice-identity/README.md).
