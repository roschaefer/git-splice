# git-splice

git-splice is a developer-friendly way to contribute to other repositories
from one monorepo. Edit them as folders, test them together, and sync both
ways with plain Git.

Keep folders of your monorepo in sync with their own repositories, in both
directions: to publish a package, mirror a library, or keep a vendored copy
up to date. Switch branches in the monorepo, and every folder switches the
branch it syncs with.

## The problem

You vendored a library into your monorepo and fixed a bug in it, tested
together with your app. Now the fix should go back to the library's own
repository, but it is buried in monorepo commits that also touch `app/`,
and the two repositories share no history:

```text
  your monorepo                              github.com/x/lib
 ┌──────────────────────────────┐           ┌─────────────────────┐
 │ app/                         │           │ src/                │
 │ vendor/lib/  (copy of x/lib) │           │ README.md           │
 │   src/       ← your fix      │ ───?───▶  │                     │
 └──────────────────────────────┘           └─────────────────────┘
   one history for app and lib                its own history
```

The same holds the other way round: a package developed in the monorepo
that you publish as its own repository, while still merging outside
contributions back in. Neither side should become the source of truth.

## The solution

Instead of copying the library, splice it in once:

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/test/readme/scrut-setup.sh"
```
-->

```scrut
$ git splice clone https://github.com/x/lib.git vendor/lib
===  vendor/lib: fetching https://github.com/x/lib.git
ok   vendor/lib: cloned e849115 from main
```

(If `vendor/lib` already holds a changed copy, `clone --merge` keeps both,
and every file that differs becomes a conflict to resolve.)

From then on, `git splice pull vendor/lib` brings upstream changes in as
one ordinary monorepo commit, and `git splice push vendor/lib` rebuilds the
monorepo commits that touched `vendor/lib/` as commits of the library,
containing only that folder. Both histories are shown as
`git log --graph --oneline` shows them, newest first:

```text
  monorepo                                    github.com/x/lib

  * (HEAD -> fix-parser) app: call parse()
  * fix parse() options          ── push ──▶  * (fix-parser) fix parse() options
  * rename helper in app and lib ── push ──▶  * rename helper in app and lib
  |                                           |
  * (main) splice: clone          ◀── clone ── * (main) e849115 release 1.2
  |   vendor/lib from main at e849115
  * app: initial commit
```

Point the URL at your fork, and the pushed branch is ready for a pull
request. Changes cross the boundary, but commits don't: both repositories
keep their own histories.

The splice's state is one committed file:

```scrut
$ cat vendor/lib/.splice
[splice]
	url = https://github.com/x/lib.git
	commit = e8491155fe5db4e87fd6c1227ab65fd61da8af0a
```

`commit` is the sync point: the upstream commit the folder last matched.
Everything else follows from two rules:

1. **The folder carries its own state.** Move it with `git mv`, and the
   splice moves along. Push unpushed commits first: a push after the move
   squashes them into it
   ([#4](test/scenarios/moved-with-unpushed-commits/README.md)). A clone of the monorepo has every splice, with no
   setup.
2. **Your local branch name is the upstream branch name.** On `feature-x`,
   every splice syncs with its upstream's `feature-x`. On the monorepo's
   default branch, it syncs with the upstream's default branch, whatever
   its name ([example](test/scenarios/default-branch/README.md)).

[The design](docs/design/README.md) explains the model, how it
[compares](docs/design/README.md#how-it-compares) to `git submodule`,
`git subtree`, git-subrepo, Josh, Copybara and others, and its
[limits](docs/design/README.md#limits).

## Getting started

Head over to the [documentation](https://roschaefer.github.io/git-splice/) to
[install git-splice](https://roschaefer.github.io/git-splice/docs/installation/), look up its
[commands](https://roschaefer.github.io/git-splice/docs/commands/) and
[sync states](https://roschaefer.github.io/git-splice/docs/sync-states/), and follow
[a walkthrough of every command](https://roschaefer.github.io/git-splice/test/walkthrough/).

## Contribute

- [Contributing](CONTRIBUTING.md)

## License

MIT, see [LICENSE](LICENSE).
