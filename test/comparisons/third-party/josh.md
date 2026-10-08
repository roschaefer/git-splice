# Josh compared

[Josh](https://github.com/josh-project/josh), "Just One Single History",
shows a folder of a monorepo as a repository of its own by filtering the
monorepo's history. Its filters are reversible: filtering a commit always
gives the same commit, and filtering the result back gives the original.
So the library's repository and the monorepo share commits, hash for hash,
but only if the monorepo holds the library's whole history.

git-splice keeps the two histories apart. This page runs both on the same
library and monorepo, with `josh-filter`, Josh's command-line front end to
its filters, the way Josh's
[import guide](https://josh-project.github.io/josh/guide/importing.html)
uses it. It shows that the library gets the same commits from both tools,
and what the monorepo has to hold for that.

The setup: `https://git.example.com/lib.git`, a library with 30 commits,
and a monorepo with an app. [How these pages run](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../scrut-setup.sh"
```
-->

```scrut
$ josh-filter --version
Version: r24.10.04
```

## Import the library

Josh imports the library by rewriting its history as if it had always been
developed in `vendor/lib/`, and merging that into the monorepo:

```scrut
$ git fetch -q https://git.example.com/lib.git main && josh-filter ':prefix=vendor/lib' FETCH_HEAD && git merge -q --allow-unrelated-histories -m "import vendor/lib" FILTERED_HEAD
```

The monorepo now has a copy of each of the library's 30 commits, with
other hashes, since their trees have the files under `vendor/lib/`:

```scrut
$ git log --oneline -2 FILTERED_HEAD
aa49e17 lib commit 30
7934fd0 lib commit 29
```

Filtering `vendor/lib/` out of the monorepo gives back the library's own
commits:

```scrut
$ josh-filter ':/vendor/lib' && git rev-parse FILTERED_HEAD && git -C "$COMPARISON/upstream/lib.git" rev-parse main
bafd496b1f4512a95b69464604f3da428aa9e33b
bafd496b1f4512a95b69464604f3da428aa9e33b
```

## Fix the library: the same commit

You fix the library and use the fix in the app, in one commit:

```scrut
$ echo "fix" >>vendor/lib/src/parse.txt && echo "call parse()" >>app/main.txt && git commit -q -a -m "fix parse() and call it"
```

Filtered, it's a library commit on top of the library's `main`, which the
library could take as a fast-forward:

```scrut
$ josh-filter ':/vendor/lib' && git log --oneline -2 FILTERED_HEAD
5069701 fix parse() and call it
bafd496 lib commit 30
```

The same fix with `git splice`, which brings in no history:

```scrut
$ cd ../splice-monorepo && git splice clone https://git.example.com/lib.git vendor/lib
===  vendor/lib: fetching https://git.example.com/lib.git
ok   vendor/lib: cloned bafd496 from main
```

```scrut
$ echo "fix" >>vendor/lib/src/parse.txt && echo "call parse()" >>app/main.txt && git commit -q -a -m "fix parse() and call it" && git splice push vendor/lib
ok   vendor/lib: pushed 5069701 to main
```

The library gets 5069701 from both. Josh and git-splice copy a commit's
author, committer, dates and message the way `git subtree split` does, so
the same change on top of the same library commit is the same commit.
Neither needs to remember which commits it pushed: it computes them again.

## Both sides move on

The library gets a release:

```scrut
$ git clone -q https://git.example.com/lib.git ../lib-dev && echo "release 1.3" >>../lib-dev/src/parse.txt && git -C ../lib-dev commit -q -a -m "release 1.3" && git -C ../lib-dev push -q
```

Meanwhile, each monorepo adds notes to the library:

```scrut
$ echo "notes" >vendor/lib/NOTES && git add vendor/lib && git commit -q -m "add notes to lib"
```

```scrut
$ cd ../monorepo && echo "notes" >vendor/lib/NOTES && git add vendor/lib && git commit -q -m "add notes to lib"
```

### Josh: merge in the filtered history

The release and the notes now diverge, and Josh merges them in the
library's history, where both sides share commits. A worktree of the
filtered history stands in for a checkout of Josh's view:

```scrut
$ git fetch -q https://git.example.com/lib.git main:refs/lib/main && josh-filter ':/vendor/lib' && git worktree add -q --detach ../lib-view FILTERED_HEAD && git -C ../lib-view merge -q -m "merge release 1.3" refs/lib/main
```

`--reverse` carries the merge back into the monorepo, here into a ref that
`main` then fast-forwards to:

```scrut
$ git update-ref FILTERED_HEAD "$(git -C ../lib-view rev-parse HEAD)" && git update-ref refs/josh/main main && josh-filter --reverse ':/vendor/lib' refs/josh/main && git merge -q --ff-only refs/josh/main
```

The release reaches the monorepo as a commit of its own, joined by the
merge:

```scrut
$ git log --oneline --graph -4
*   98c80a6 merge release 1.3
|\  
| * 8adb05a release 1.3
* | d0af3c0 add notes to lib
|/  
* 95dc6e0 fix parse() and call it
```

### git-splice: one pull commit

```scrut
$ cd ../splice-monorepo && git splice pull vendor/lib
ok   vendor/lib fetched (main moved 5069701..ab8d849)
ok   vendor/lib: pulled ab8d849
```

```scrut
$ git log --oneline --graph -3
* c53163d splice: pull vendor/lib from main at ab8d849
* 9b79bcc add notes to lib
* ae63bb6 fix parse() and call it
```

The release stays in the library's history, in `refs/splices/lib/main`.
The monorepo's history counts its own commits only:

```scrut
$ git rev-list --count HEAD && git -C ../monorepo rev-list --count HEAD
44
75
```

## Where Josh is different

- **History, not a sync point.** Josh needs no sync point: a commit's
  filtered hash says where the two sides meet. git-splice records that
  meeting point, the synced commit, in `.splice`, so it needs no shared
  history. Josh's own design for repositories it didn't import, such as
  `rust-lang/miri` next to `rust-lang/rust`, lists how to relate them at
  their sync points as an
  [open question](https://github.com/josh-project/josh/blob/master/rfcs/worktree.md#open-questions).
  Today, the external
  [`rustc-josh-sync`](https://github.com/rust-lang/josh-sync) keeps the
  last synced commit in a `rust-version` file of the smaller repository.
- **Git does less of the work.** Josh filters, walks history and merges
  trees in Rust, on gitoxide, with a cache, so it can filter whole
  histories quickly, and calls the `git` command for fetches and pushes.
  git-splice calls Git for every step, and only walks history since the
  last sync.
- **The monorepo is where Josh starts.** Its views, `josh clone` and
  `josh-proxy` serve folders of the monorepo to people who work on just
  that folder. git-splice starts from a library that has its own
  repository, and keeps working in the monorepo, where the library is
  tested with the app.
- **Links are newer, and go one way.** The experimental `josh link`
  publishes a folder to a repository of its own. A link's id and the one
  upstream branch it tracks live in a ref of the monorepo,
  `refs/josh/links/<id>`, not in the folder, and nothing comes back
  through a link. A splice's id and synced commit are committed in its
  folder, so they move along with `git mv`, and each monorepo branch syncs
  with the upstream branch of its name.

## In short

| | Josh | `git splice` |
| --- | --- | --- |
| Library history in the monorepo | whole, as copies under the folder | none, one commit per sync |
| Commits a push sends | the filtered history, the same as `git subtree split` | the commits since the last sync, the same as `git subtree split` |
| Where both sides meet | shared commits | the synced commit in `.splice` |
| An upstream commit pulled in | one monorepo commit for each, merged | one pull commit for all |
| Monorepo history | merges | linear |
| Implementation | Rust, gitoxide, a cache | Bash, the `git` command |
| Best for | a monorepo that is the source of truth, served in parts | a library with its own repository, changed in the monorepo |
