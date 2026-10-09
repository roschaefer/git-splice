# Josh compared

[Josh](https://github.com/josh-project/josh), "Just One Single History",
shows a folder of a monorepo as a repository of its own by filtering the
monorepo's history. Its filters are reversible: filtering a commit always
gives the same commit, and filtering the result back gives the original.
So the library's repository and Josh's filtered view of the monorepo share
commits, hash for hash, but only if the monorepo holds the library's whole
history, as copies of its commits.

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
the same unsigned change on top of the same library commit is the same
commit. A signed commit differs: Josh keeps its signature header by
default, which then no longer verifies, and git-splice never signs.
Neither needs to remember which commits it pushed: it computes them again.

## A release breaks the app: `git bisect`

The app's test needs the fix in the library:

```scrut
$ printf '%s\n' 'grep -q "call parse()" app/main.txt && grep -qx fix vendor/lib/src/parse.txt' >"$COMPARISON/test-app.sh" && sh "$COMPARISON/test-app.sh" && echo pass
pass
```

The library gets four commits, and one of them renames the line the app
relies on:

```scrut
$ git clone -q https://git.example.com/lib.git ../lib-release && cd ../lib-release && echo "parse(text)" >README.md && git add README.md && git commit -q -m "docs: explain parse()" && sed -i 's/^fix$/fixed/' src/parse.txt && git commit -q -a -m "parse: rename fix to fixed"
```

```scrut
$ echo "example" >examples.txt && git add examples.txt && git commit -q -m "add examples" && echo "1.2" >VERSION && git add VERSION && git commit -q -m "release 1.2" && git push -q && cd ../splice-monorepo
```

### Josh: the culprit is a monorepo commit

The Josh monorepo hasn't changed the library since the fix, so the
library's commits land on top of it. `--reverse` turns each into a
monorepo commit, here into a ref that `main` then fast-forwards to:

```scrut
$ cd ../monorepo && git fetch -q https://git.example.com/lib.git main && git update-ref FILTERED_HEAD FETCH_HEAD && git update-ref refs/josh/main main && josh-filter --reverse ':/vendor/lib' refs/josh/main && git merge -q --ff-only refs/josh/main
```

```scrut
$ git log --oneline -5
99943ff release 1.2
372e8a6 add examples
092b6b1 parse: rename fix to fixed
0ea8b10 docs: explain parse()
95dc6e0 fix parse() and call it
```

The test fails now, and `git bisect` finds the library's commit among the
monorepo's own:

```scrut
$ git bisect start HEAD HEAD~4 >/dev/null && git bisect run sh "$COMPARISON/test-app.sh" >/dev/null && git bisect log | tail -1 && git bisect reset >/dev/null
# first bad commit: [092b6b1e37d8035965e55a4856c921988c941e39] parse: rename fix to fixed
```

### git-splice: the culprit is the pull

```scrut
$ cd ../splice-monorepo && git splice pull vendor/lib
ok   vendor/lib fetched (main moved 5069701..612d462)
ok   vendor/lib: pulled 612d462
```

`git bisect` stops at the pull, which brought all four commits at once:

```scrut
$ git bisect start HEAD HEAD~1 >/dev/null && git bisect run sh "$COMPARISON/test-app.sh" >/dev/null && git bisect log | tail -1 && git bisect reset >/dev/null
# first bad commit: [f85ff0501eca7cb3482ec7e84b7da5fd966724d5] splice: pull vendor/lib from main at 612d462
```

To go deeper, bisect the library's history between the two synced
commits, U1 and U2, which `.splice` records before and after the pull. Its
commits are fetched into the monorepo already, so a worktree of the
monorepo can check them out. A second, throwaway worktree runs the app's
test, so your own checkout stays as it is:

```scrut
$ git worktree add -q --detach ../app-bisect && git worktree add -q --detach ../lib-bisect && cd ../lib-bisect && git bisect start "$(git config --blob HEAD:vendor/lib/.splice splice.commit)" "$(git config --blob HEAD~1:vendor/lib/.splice splice.commit)" >/dev/null
```

The library alone can't run the app's test, so each step replaces the
throwaway worktree's folder with the library's files at that step:

```scrut
$ git bisect run sh -c 'rm -rf ../app-bisect/vendor/lib && mkdir ../app-bisect/vendor/lib && git archive HEAD | tar -x -C ../app-bisect/vendor/lib && cd ../app-bisect && sh "$COMPARISON/test-app.sh"' >/dev/null && git bisect log | tail -1
# first bad commit: [9c8481ced0e577e419cebdf1caa1d444e05944f7] parse: rename fix to fixed
```

```scrut
$ git bisect reset >/dev/null && cd ../splice-monorepo && git worktree remove ../lib-bisect && git worktree remove --force ../app-bisect
```

That's the library's own commit, of which Josh's `092b6b1` is the
monorepo's copy. Replacing the folder works here because it had no
changes of its own since U1. With unpushed changes, each step would need
them merged in.

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
*   151bbf6 merge release 1.3
|\  
| * 148e97c release 1.3
* | 64fc20e add notes to lib
|/  
* 99943ff release 1.2
```

### git-splice: one pull commit

```scrut
$ cd ../splice-monorepo && git splice pull vendor/lib
ok   vendor/lib fetched (main moved 612d462..bc443d9)
ok   vendor/lib: pulled bc443d9
```

```scrut
$ git log --oneline --graph -3
* 49407e9 splice: pull vendor/lib from main at bc443d9
* 5b9db00 add notes to lib
* f85ff05 splice: pull vendor/lib from main at 612d462
```

The release stays in the library's history, in `refs/splices/lib/main`.
The monorepo's history counts its own commits only:

```scrut
$ git rev-list --count HEAD && git -C ../monorepo rev-list --count HEAD
45
79
```

## Whose history is it?

With Josh, the library's history is a view of the monorepo's: one
project, seen through a folder. With git-splice, the library has a history
of its own, and the monorepo integrates it. The difference shows when the
monorepo adopts a library change on a branch, glues it into the app, and
merges the branch.

In the Josh monorepo, the branch changes the library, adapts the app, and
fixes a typo in the library change:

```scrut
$ cd ../monorepo && git switch -q -c parse-options && echo "options" >vendor/lib/src/options.txt && git add vendor/lib && git commit -q -m "lib: add parse() options" && echo "parse(options)" >>app/main.txt && git commit -q -a -m "app: pass options to parse()" && echo "options, fixed" >vendor/lib/src/options.txt && git commit -q -a -m "lib: fix options typo"
```

```scrut
$ git switch -q main && echo "deps" >app/deps.txt && git add app && git commit -q -m "app: bump dependencies" && git merge -q --no-ff -m "Merge branch 'parse-options'" parse-options
```

The library gets the monorepo's merge, with its branch name, and both of
the branch's library commits, the typo fix included. Only the commits that
didn't touch the library, the app's glue and the dependency bump, stay
behind:

```scrut
$ josh-filter ':/vendor/lib' && git log --oneline --graph -6 FILTERED_HEAD
*   2788671 Merge branch 'parse-options'
|\  
| * 3b58a7e lib: fix options typo
| * 0833578 lib: add parse() options
|/  
*   23ff56b merge release 1.3
|\  
| * bc443d9 release 1.3
* | 15560d7 add notes to lib
|/  
```

The same branch and merge in the git-splice monorepo:

```scrut
$ cd ../splice-monorepo && git switch -q -c parse-options && echo "options" >vendor/lib/src/options.txt && git add vendor/lib && git commit -q -m "lib: add parse() options" && echo "parse(options)" >>app/main.txt && git commit -q -a -m "app: pass options to parse()" && echo "options, fixed" >vendor/lib/src/options.txt && git commit -q -a -m "lib: fix options typo"
```

```scrut
$ git switch -q main && echo "deps" >app/deps.txt && git add app && git commit -q -m "app: bump dependencies" && git merge -q --no-ff -m "Merge branch 'parse-options'" parse-options
```

A push follows the monorepo's first parents, so the merge reaches the
library as one commit, with the library's half of the branch:

```scrut
$ git splice push vendor/lib
ok   vendor/lib: pushed ea668f6 to main
```

```scrut
$ git -C "$COMPARISON/upstream/lib.git" log --oneline --graph -6 main
* ea668f6 Merge branch 'parse-options'
*   ef0b95a splice: pull vendor/lib from main at bc443d9
|\  
| * bc443d9 release 1.3
* | 15560d7 add notes to lib
|/  
* 612d462 release 1.2
* efa30d9 add examples
```

Below it, both libraries have the same merge of the earlier pull: the same
parents, `15560d7` and `bc443d9`, with Josh's message or git-splice's.
A merge that joins the library's own history with the monorepo's changes
belongs to the library, and both tools send it. A merge of the monorepo's
branches is integration, and only Josh sends it.

The message is still the monorepo's: `Merge branch 'parse-options'`. A
squash merge, or a merge message written for the library, reaches the
library as written.

## Where Josh is better

- **`git bisect`, `git blame` and `git log` reach the library's commits.**
  In the Josh monorepo, they're ancestors, so a
  [bisect](#a-release-breaks-the-app-git-bisect) lands on the library's
  commit, and blame names its author. In the git-splice monorepo, they
  stop at the pull that brought the commits in, and going further takes a
  second bisect, `git log`, or `git blame` on the library's history,
  between the synced commits.
- **Nothing to conflict on a pull.** Two monorepo branches that both pull a
  splice conflict in `.splice`, and you keep the newer synced commit. Josh
  stores no sync point, so there's nothing to resolve but the files.
- **Any slice of the monorepo can be a repository.** A view can combine
  folders, change on demand and be served to people who can't see the rest
  of the monorepo. A splice is one folder with one upstream, set up
  beforehand.
- **Built for large monorepos.** Josh filters whole histories quickly,
  with a cache that can be shared between machines.

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
- **Links are unreleased, and go one way.** `josh link`, experimental
  and on Josh's `master` since September 2026 but in no release yet,
  publishes a folder to a repository of its own. A link's id and the one
  upstream branch it tracks live in a ref of the monorepo,
  `refs/josh/links/<id>`, not in the folder, and nothing comes back
  through a link. A splice's id and synced commit are committed in its
  folder, so they move along with `git mv`, and each monorepo branch syncs
  with the upstream branch of its name, the default branch with the
  upstream's.

## In short

| | Josh | `git splice` |
| --- | --- | --- |
| Library history in the monorepo | whole, as copies under the folder | none, one commit per sync |
| Commits a push sends | the filtered history, the same as `git subtree split` for unsigned commits | the first-parent commits since the last sync, otherwise the same as `git subtree split` |
| `git bisect` for a library bug | finds the monorepo's copy of the library's commit | finds the pull, then a second bisect between the synced commits does |
| A monorepo branch merged | a merge, with the branch's commits | one commit, with the merge's message |
| Where both sides meet | commits of the filtered view that the library has | the synced commit in `.splice` |
| An upstream commit pulled in | one monorepo commit for each, and a merge if both sides moved | one pull commit for all |
| Merges a sync adds to the monorepo | one when both sides moved | none |
| Implementation | Rust, gitoxide, a cache | Bash, the `git` command |
| Best for | a monorepo that is the source of truth, served in parts | a library with its own repository, changed in the monorepo |
