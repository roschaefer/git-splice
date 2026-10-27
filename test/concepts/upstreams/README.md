# Upstreams

An upstream is a repository a splice syncs with. `.splice` names it and
stores its URL:

```text
[upstream "origin"]
	url = https://git.example.com/s.git
```

The name works like a Git remote name, but no remote is created. A splice
can name several upstreams, such as a fork and the original;
`default-upstream` selects one unless a command uses `--upstream`
([example](../../scenarios/04-upstreams/02-several-upstreams/README.md)).

## URLs, keys and refs

The monorepo identifies an upstream by its URL. The first fetch gives that
URL a short local *key* and stores its branches under
`refs/splices/<key>/heads/`.

| State | One per |
|---|---|
| `.splice`, `id`, synced commit | splice |
| key, fetched refs | upstream URL |

Splices with the same URL therefore share fetched refs, but each keeps its
own synced commit.

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

Both splices use the same key and fetched branch:

```scrut
$ git splice key app-a/s && git splice key app-b/s
s
s
```

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
