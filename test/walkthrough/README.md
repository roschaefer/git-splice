# Walkthrough

`just walkthrough` builds a throwaway monorepo in a temporary directory and
opens a shell in it. This page runs every command there once, in order,
with the output each one prints. Each command has a page of its own with
the details. CI runs these pages with
[scrut](https://facebookincubator.github.io/scrut/), so the output is what
the current version prints (`just docs-check`).

What you get:

- `$WALKTHROUGH/monorepo`: the monorepo, on `main`. You start here.
- `$WALKTHROUGH/upstream/pkg-a.git`, `pkg-b.git` and `lib-c.git`: bare
  repositories on the same machine that stand in for the splices'
  upstreams. The monorepo reaches them as
  `https://git.example.com/<name>.git`: its `url.<base>.insteadOf` maps
  that prefix to `$WALKTHROUGH/upstream/`. The walkthrough shell exports
  `$WALKTHROUGH`, so you can paste the commands below as they are.
- `vendor/pkg-a`: a splice whose upstream has one commit the monorepo
  doesn't have yet. It's already fetched.
- `pkg-b.git`: a repository that isn't spliced in yet.
- `libs/c`: a folder of the monorepo, to be published to the empty
  `lib-c.git`.

`simulate-remote-change <path> [message]` pushes a commit to a splice's
upstream, as if someone else had.

## Commands

| Command | What it does |
| --- | --- |
| [`status`](status.md) | Shows each splice's sync state, with how many commits `push` would publish and `pull` would bring in. |
| [`clone`](clone.md) | Splices an existing repository into a new folder, as one commit. |
| [`fetch`](fetch.md) | Fetches every branch of each upstream into `refs/splices/<key>/`. |
| [`log`](log.md) | Shows the commits `push` would publish and `pull` would bring in. |
| [`merge`](merge.md) | Splices already-fetched upstream changes in, as one ordinary commit per splice. |
| [`pull`](pull.md) | `fetch` + `merge`. |
| [`diff`](diff.md) | Shows the file changes `push` would send. |
| [`push`](push.md) | Rebuilds the commits that changed each splice since the last sync and pushes them upstream. Writes nothing to the monorepo. |
| [`init`](init.md) | Makes a folder a splice of a new, empty repository. |
| [`boundary`](boundary.md) | Prints the monorepo commit where a splice last synced. |
| [`rebuild`](rebuild.md) | Prints the commit `push` would send, without pushing it. |
| [`key`](key.md) | Prints the key of a splice's upstream, or renames it, refs included. |

`clone`, `init`, `fetch`, `merge`, `pull`, `push`, `status`, `diff` and
`log` are named after Git's commands, and do to a splice what their
namesakes do to a repository. `boundary`, `rebuild` and `key` are new:
their names come from splicing.

`merge`, `pull` and `push` change the monorepo or an upstream, so they
name their splices, or take `--all`. `clone` and `init` start one splice
each, and `boundary`, `rebuild` and `key` look at one. The other commands
only look, and cover every splice unless you name some. `status`, `diff`,
`log` and `merge` only use what was last fetched. Run
`git splice <command> --help` for options.

A splice can have several [upstreams](../concepts/upstreams/README.md),
e.g. a company fork and the original it follows
([several-upstreams](../scenarios/several-upstreams/README.md)).
`--upstream <name>` picks one for `fetch`, `merge`, `pull`, `push`,
`status`, `diff`, `log` and `key`. Without it, commands use the splice's
`default-upstream`, which `.splice` needs once it names several; `fetch`
fetches all of them. A splice that lacks the named upstream stops the
command before it starts
([missing upstream names](../scenarios/several-upstreams/missing-upstream-names.md)).
Each upstream records its own `default-branch`, e.g. for a fork whose
default branch is named differently
([fork-default-branch](../scenarios/several-upstreams/fork-default-branch.md)).

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

## status

Lists every splice with its sync state ([more](status.md)):

```scrut
$ git splice status
On branch main

  behind 1  vendor/pkg-a
```

## clone

Splices in `pkg-b` ([more](clone.md)):

```scrut
$ git splice clone https://git.example.com/pkg-b.git vendor/pkg-b
===  vendor/pkg-b: fetching https://git.example.com/pkg-b.git
ok   vendor/pkg-b: cloned 9b3cb02 from main
```

## fetch

Someone pushes to `pkg-b`'s upstream. `fetch` fetches every splice's
upstream in parallel and calls out which branch moved ([more](fetch.md)):

```scrut
$ simulate-remote-change vendor/pkg-b "pkg-b: add a feature"
ok   vendor/pkg-b: pushed a new commit upstream ('pkg-b: add a feature')
     git splice status         # to see it
     git splice pull vendor/pkg-b   # to bring it in
```

```scrut
$ git splice fetch
ok   vendor/pkg-a fetched
ok   vendor/pkg-b fetched (main moved 9b3cb02..b937c4f)
```

## log

`>` marks what a pull brings in, `<` what a push publishes
([more](log.md)):

```scrut
$ git splice log
===  vendor/pkg-a (main)
> 703b936 pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
===  vendor/pkg-b (main)
> b937c4f pkg-b: add a feature  (Walkthrough <walkthrough@example.com>)
```

## merge

Splices in what was fetched, without contacting the upstream
([more](merge.md)):

```scrut
$ git splice merge vendor/pkg-a
ok   vendor/pkg-a: merged 703b936
```

## pull

`fetch` and `merge` in one ([more](pull.md)):

```scrut
$ git splice pull --all
ok   vendor/pkg-a fetched
ok   vendor/pkg-b fetched
ok   vendor/pkg-a: nothing to pull
ok   vendor/pkg-b: pulled b937c4f
```

## diff

A commit in the monorepo changes `vendor/pkg-a`. `diff` shows what `push`
would send, with paths as the upstream sees them ([more](diff.md)):

```scrut
$ echo "a local fix" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: a local fix"
```

```scrut
$ git splice diff --stat
===  vendor/pkg-a
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

## push

Sends it to the upstream branch named like yours ([more](push.md)):

```scrut
$ git splice push --all
ok   vendor/pkg-a: pushed 2d02eb8 to main
ok   vendor/pkg-b: nothing to push
```

```scrut
$ git splice status
On branch main

  up to date  vendor/pkg-a
  up to date  vendor/pkg-b
```

## init

Makes `libs/c` a splice of the empty `lib-c.git`; the first push
publishes it ([more](init.md)):

```scrut
$ git splice init libs/c https://git.example.com/lib-c.git
ok   libs/c: initialized -- 'git splice push libs/c' publishes it
```

```scrut
$ git splice push libs/c
??   libs/c: upstream has no 'main' branch yet -- this push creates it
ok   libs/c: pushed 9dc1e6a to main
```

## boundary

The monorepo commit where `vendor/pkg-a` last synced ([more](boundary.md)):

```scrut
$ git show -s --oneline "$(git splice boundary vendor/pkg-a)"
6dbb42b splice: merge vendor/pkg-a from main at 703b936
```

## rebuild

The commit `push` would send ([more](rebuild.md)):

```scrut
$ git show -s --oneline "$(git splice rebuild vendor/pkg-a)"
2d02eb8 pkg-a: a local fix
```

## key

The short name of `vendor/pkg-a`'s upstream in `refs/splices/`
([more](key.md)):

```scrut
$ git splice key vendor/pkg-a
pkg-a
```

## Next

The [sync model](../concepts/sync-model/README.md) explains what these
commands compute, and the [scenarios](../scenarios/README.md) show them
in many more situations, e.g. on
[feature branches](feature-branches.md) or with
[diverged history](diverged.md).
