# git-splice

git-splice is a developer-friendly way to contribute to other repositories
from one monorepo. Edit them as folders, test them together, and sync both
ways with plain Git.

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
 │   src/       <- your fix     │ ───?───>  │                     │
 └──────────────────────────────┘           └─────────────────────┘
   one history for app and lib                its own history
```

Meanwhile the library moves on, and its next release should come in
without overwriting your fix. The same holds the other way round: a
package developed in the monorepo that you publish as its own repository,
while still merging outside contributions back in. Neither side should
become the source of truth.

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

The folder is now a splice: a folder of the monorepo that is also the
library. One committed file inside it says which repository, and the sync
point **U**, the library commit the folder last matched:

```text
  monorepo/
  ├── app/
  └── vendor/lib/
      ├── .splice    url    = https://github.com/x/lib.git
      │              commit = U
      └── src/
```

In the real file, U is a commit hash:

```scrut
$ cat vendor/lib/.splice
[splice]
\tid = 87675ced26a59d2e (escaped)
	commit = e8491155fe5db4e87fd6c1227ab65fd61da8af0a
[upstream "origin"]
	url = https://github.com/x/lib.git
```

From U, both sides move on. Say you fix a bug in the library while working
on the app, and the library gets a release meanwhile:

<!--
```scrut
$ source "$TESTDIR/test/readme/both-sides-move-on.sh"
```
-->

```text
  monorepo, newest first                    github.com/x/lib, since U

  . app: call parse()
  * fix parse() options                     * release 1.3
  . app: bump dependencies                  * docs: explain parse()
  * rename helper in app and lib            |
  = splice: clone vendor/lib (folder = U)   |
   \                                       /
    `----------------- U -----------------'
```

On the left, `*` marks the commits that touch `vendor/lib/`, and `.` those
that don't. The clone, `=`, touches it too, but only to make the folder
match U, so it has nothing for the library.

That's a branch and its tracking branch since their merge base, and
git-splice handles it like Git does:

```scrut
$ git splice status
ok   vendor/lib -> main (diverged: ahead 2, behind 2)
```

- **Ahead 2**: the `*` commits on the left, which the library lacks.
  `git splice push vendor/lib` rebuilds them as commits of the library,
  each containing only that folder's changes.
- **Behind 2**: the library's commits since U, on the right, which the
  folder lacks.
  `git splice pull vendor/lib` merges them in as one ordinary monorepo
  commit, and moves U to the library's newest commit.

When both sides moved, as here, pull first, then push, as with
`git pull` and `git push`. Point the URL at your fork, and the pushed
branch is ready for a pull request. Changes cross the boundary, but
commits don't: both repositories keep their own histories.

Everything else follows from two rules:

1. **The folder carries its own state.** Move it with `git mv`, and the
   splice moves along, unpushed commits included
   ([example](test/scenarios/up-to-date/push-ahead/moved-with-unpushed-commits/README.md)).
   A clone of the monorepo has every splice, with no setup.
2. **Your local branch name is the upstream branch name.** On `feature-x`,
   every splice syncs with its upstream's `feature-x`. On the monorepo's
   default branch, it syncs with the upstream's default branch, whatever
   its name ([example](test/scenarios/default-branch/README.md)).

[The design](docs/design/README.md) explains the model and its
[limits](docs/design/README.md#limits).
[Comparisons](test/comparisons/README.md) shows how it compares to
`git submodule`, `git subtree`, git-subrepo, Josh, Copybara and others.

## Getting started

Head over to the
[getting started guide](https://roschaefer.github.io/git-splice/docs/installation/)
to install git-splice, learn its commands and sync states, and follow a
walkthrough of every command.

## Contribute

- [Contributing](CONTRIBUTING.md)

## License

MIT, see [LICENSE](LICENSE).
