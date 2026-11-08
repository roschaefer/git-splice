# Sapling compared

[Sapling](https://sapling-scm.com/), the version control system of Meta's
monorepo, has
[directory branching](https://engineering.fb.com/2025/10/16/developer-tools/branching-in-a-sapling-monorepo/):
`sl subtree` copies a folder, or an external Git repository, into a folder,
and later merges changes between the two with an ordinary three-way merge.
Like `git-splice`, it brings in no history: each import or merge is one
commit, and it records the commit it came from, the merge base of the next
merge.

`git-splice` records that commit in a file, `.splice`. Sapling records it in
the commit, as metadata that Git sees as an extra commit header. This page
runs both on the same library and monorepo, with Sapling working directly
in the monorepo's Git repository. It shows where each one keeps the record,
what that means for a squash merge, and which way changes can go.

The main distinction is where the sync record lives. Sapling understands
its commit metadata and preserves it through its own rewrites; a Git squash
can discard it. `.splice` is part of the tree and survives the squash.

| | Sapling `sl subtree` | `git-splice` |
| --- | --- | --- |
| Library history in the monorepo | none, one commit per import or merge | none, one commit per sync |
| Where the merge base is recorded | the commit's metadata, an extra header to Git | `.splice`, a file in the folder |
| After a squash merge or `git rebase` | gone, an older record is used, or the merge aborts if there's none | kept |
| Changes back to the library | by hand, a patch per commit | `git splice push` |
| `log` and `blame` into the library | `sl log`, `sl blame`, from the import | a second `git log` on the library's history |
| Two folders of one repository | `sl subtree copy` and `merge` | not supported |
| Tools | Sapling | Git |

Sapling also supports branching folders within one repository and following
history across those copies with `sl log` and `sl blame`. A splice connects
a folder to a separate repository. Sapling's metadata avoids conflicts in
a sync-state file; it does not prevent conflicts in the code.

The commands below use the Sapling version pinned in
[`flake.nix`](../../../flake.nix). External `merge --url` and `graft --url`
are experimental in that version. Native integration ideas are in
[Going forward](../../08-going-forward/04-sapling.md).

The setup: `https://git.example.com/lib.git`, a library with 30 commits,
and a monorepo with an app. [How these pages run](../01-git/README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../scrut-setup.sh"
```
-->

<!-- The flake packages Sapling for Linux only; elsewhere scrut skips
this page. -->
<!--
```scrut
$ [[ "$(uname -s)" == Linux ]] || exit 80
```
-->

<!-- Sapling's settings, its cache of external repositories, and fixed
dates, so commit hashes are the same on every run. -->
<!--
```scrut
$ export HOME="$COMPARISON/home" XDG_CONFIG_HOME="$COMPARISON/home/.config" && mkdir -p "$XDG_CONFIG_HOME/sapling" && printf '[ui]\nusername = App Dev <app@example.com>\n[devel]\ndefault-date = 1767225600 0\n' >"$XDG_CONFIG_HOME/sapling/sapling.conf" && sl() { command sl "$@" 2>&1 | sed -E "s#$COMPARISON#\$COMPARISON#g"; return "${PIPESTATUS[0]}"; }
```
-->

```scrut
$ sl --version 2>/dev/null | head -1
Sapling 0.2.20260929-102736+288e0c2d
```

## Import the library

`sl subtree import` copies a commit of the library into a folder, as one
commit. It fetches the library into a cache of its own, outside the
monorepo:

```scrut
$ sl subtree import \
>   --url https://git.example.com/lib.git --rev main --to-path vendor/lib \
>   -m "import vendor/lib"
creating git repo at $COMPARISON/home/.sl_cache/gitrepos/316067af85b8bd24e96f811d9f55a8f2d20eed8dcae7796fe42d9eb9ea621a17
From $COMPARISON/upstream/lib
 * [new ref]         bafd496b1f4512a95b69464604f3da428aa9e33b -> remote/main
1 files updated, 0 files merged, 0 files removed, 0 files unresolved
copying / to vendor/lib
```

To Git, the record is an extra header of that commit, `test_subtree`, with
the library's URL, the commit, and the two paths:

```scrut
$ git cat-file -p HEAD
tree 958b85b6b9e0f8bb5a1349336a894220df5f8fdb
parent 7de219808bfd601897cdad67aa5c90b5a2e9bce8
author App Dev <app@example.com> 1767225600 +0000
committer App Dev <app@example.com> 1767225600 +0000
test_subtree [{"imports":[{"from_commit":"bafd496b1f4512a95b69464604f3da428aa9e33b","from_path":"","to_path":"vendor/lib","url":"https://git.example.com/lib.git"}],"v":1}]

import vendor/lib

Subtree import from https://git.example.com/lib.git at bafd496b1f4512a95b69464604f3da428aa9e33b
- Imported path root directory to vendor/lib
```

### With `git-splice`: a file in the folder

`git-splice` writes the same facts into `.splice`:

```scrut
$ cd ../splice-monorepo && git splice clone https://git.example.com/lib.git vendor/lib
===  vendor/lib: fetching https://git.example.com/lib.git
ok   vendor/lib: cloned bafd496 from main
```

```scrut
$ cat vendor/lib/.splice
[splice]
	id = f34fc447facba9d0
	commit = bafd496b1f4512a95b69464604f3da428aa9e33b
[upstream "origin"]
	url = https://git.example.com/lib.git
```

## Fix the library: no way back

You fix the library and use the fix in the app, in one commit:

```scrut
$ cd ../monorepo &&
>   echo "fix" >>vendor/lib/src/parse.txt &&
>   echo "call parse()" >>app/main.txt &&
>   git commit -q -a -m "fix parse() and call it"
```

`sl subtree` has no command that sends it to the library: `import`,
`merge` and `graft` only bring changes in. Plain Git can carry the
library's half of one commit over to a clone of the library, as a patch:

```scrut
$ git clone -q https://git.example.com/lib.git ../lib-patch &&
>   git format-patch --relative=vendor/lib -1 --stdout | git -C ../lib-patch am -q &&
>   git -C ../lib-patch log --oneline -2
5069701 fix parse() and call it
bafd496 lib commit 30
```

### With `git-splice`: a push

`git-splice` finds the commits since the last sync and pushes them:

```scrut
$ cd ../splice-monorepo &&
>   echo "fix" >>vendor/lib/src/parse.txt &&
>   echo "call parse()" >>app/main.txt &&
>   git commit -q -a -m "fix parse() and call it" &&
>   git splice push vendor/lib
ok   vendor/lib: pushed 5069701 to main
```

The patch, applied by hand, gave the same commit. For one commit, that's
the work `git splice push` saves. For several, a branch, or a merge in the
monorepo, see [what a push sends](../02-third-party/02-josh.md#whose-history-is-it).

## Both sides move on

The library gets a release:

```scrut
$ git clone -q https://git.example.com/lib.git ../lib-dev &&
>   echo "1.3" >../lib-dev/VERSION &&
>   git -C ../lib-dev add VERSION &&
>   git -C ../lib-dev commit -q -m "release 1.3" &&
>   git -C ../lib-dev push -q
```

Meanwhile, each monorepo adds notes to the library:

```scrut
$ echo "notes" >vendor/lib/NOTES &&
>   git add vendor/lib &&
>   git commit -q -m "add notes to lib"
```

```scrut
$ cd ../monorepo &&
>   echo "notes" >vendor/lib/NOTES &&
>   git add vendor/lib &&
>   git commit -q -m "add notes to lib"
```

`sl subtree merge --url` merges a commit of the library into the folder.
It takes a commit id here: a branch name would be looked up in Sapling's
cache, which still has `main` from the import.
It walks back through the folder's history to the newest record, and
merges from the commit that record names:

```scrut
$ sl subtree merge \
>   --url https://git.example.com/lib.git \
>   -r "$(git ls-remote https://git.example.com/lib.git main | cut -f1)" \
>   --to-path vendor/lib
using cached git repo at $COMPARISON/home/.sl_cache/gitrepos/316067af85b8bd24e96f811d9f55a8f2d20eed8dcae7796fe42d9eb9ea621a17
pulling '9a471d297ba8ec16f7c58d0b7c379b4c706a8664' from 'https://git.example.com/lib.git'
searching for merge base ...
found the last subtree import commit df38cc67c1a8
merge base: bafd496b1f45
update complete
(subtree merge, don't forget to commit)
```

The fix is on both sides, so only the release and the notes remain. The
merge leaves the working copy to commit:

```scrut
$ sl commit -m "merge lib release 1.3" >/dev/null && git log --oneline -4
b41e133 merge lib release 1.3
f7e7ca2 add notes to lib
1f52bd9 fix parse() and call it
df38cc6 import vendor/lib
```

```scrut
$ git cat-file -p HEAD | grep '^test_subtree'
test_subtree [{"v":1,"xmerges":[{"from_commit":"9a471d297ba8ec16f7c58d0b7c379b4c706a8664","from_path":"","to_path":"vendor/lib","url":"https://git.example.com/lib.git"}]}]
```

### With `git-splice`: one pull

```scrut
$ cd ../splice-monorepo && git splice pull vendor/lib
ok   vendor/lib fetched (main moved 5069701..9a471d2)
ok   vendor/lib: pulled 9a471d2
```

```scrut
$ git log --oneline -3
7427f19 splice: pull vendor/lib from main at 9a471d2
53ca8c1 add notes to lib
22698ef fix parse() and call it
```

Both monorepos now have one commit per sync, and a linear history.

## `sl log` reaches the library's commits

The import's record names the library and its commit, so `sl log` goes on
into the library's history, from Sapling's cache:

```scrut
$ cd ../monorepo && sl log -l 6 -T '{node|short} {desc|firstline}\n' vendor/lib
b41e133c9846 merge lib release 1.3
f7e7ca2c1aef add notes to lib
1f52bd9118f5 fix parse() and call it
df38cc67c1a8 import vendor/lib
bafd496b1f45 lib commit 30
eacfd6697aff lib commit 29
```

Git's own `git log` stops at the import.

### With `git-splice`: `git log` on the library's history

`git log` stops at the clone, too. The library's commits are fetched into
the monorepo's repository, so `git log` can go on in the library's
history
([bisecting into a pull](../02-third-party/02-josh.md#with-git-splice-the-culprit-is-the-pull)).

## A squash merge drops the record

The library prepares its next release on a branch, `release-1.4`, and it
adds a file:

```scrut
$ git -C ../lib-dev switch -q -c release-1.4 &&
>   echo "compat" >../lib-dev/src/compat.txt &&
>   git -C ../lib-dev add src &&
>   git -C ../lib-dev commit -q -m "release 1.4: add compat" &&
>   git -C ../lib-dev push -q origin release-1.4
```

Each monorepo tries it on a branch of the same name, and squash-merges
that branch into `main`, as a pull request on GitHub can. First Sapling's:

```scrut
$ git switch -q -c release-1.4 &&
>   sl subtree merge \
>     --url https://git.example.com/lib.git \
>     -r "$(git ls-remote https://git.example.com/lib.git release-1.4 | cut -f1)" \
>     --to-path vendor/lib >/dev/null &&
>   sl commit -m "merge lib release 1.4" >/dev/null
```

```scrut
$ git switch -q main &&
>   git merge -q --squash release-1.4 &&
>   git commit -q -m "merge lib release 1.4 (#12)"
Squash commit -- not updating HEAD
```

The squash commit has the release's files, but no record:

```scrut
$ sl subtree inspect
no subtree metadata found for commit 289ff1b89a63
```

### With `git-splice`: the file stays

A pull on `release-1.4` follows the library's branch of that name:

```scrut
$ cd ../splice-monorepo && git switch -q -c release-1.4 && git splice pull vendor/lib
ok   vendor/lib fetched
ok   vendor/lib: pulled 5bb7733
```

```scrut
$ git switch -q main &&
>   git merge -q --squash release-1.4 &&
>   git commit -q -m "merge lib release 1.4 (#12)"
Squash commit -- not updating HEAD
```

`.splice` is a file in the folder, so the squash commit has it, with
the release's commit:

```scrut
$ git config --file vendor/lib/.splice splice.commit
5bb77336f81e232ae81a98e1d4a741b22cefe476
```

## The next release removes the file again

The library merges `release-1.4` and then drops the file in 1.5:

```scrut
$ git -C ../lib-dev switch -q main &&
>   git -C ../lib-dev merge -q --ff-only release-1.4 &&
>   git -C ../lib-dev rm -q src/compat.txt &&
>   git -C ../lib-dev commit -q -m "release 1.5: drop compat" &&
>   git -C ../lib-dev push -q
```

Sapling finds the newest record it can, the merge of 1.3, and merges from
there. From that base, the monorepo added `compat.txt` and the library
left it alone, so the merge keeps it:

```scrut
$ cd ../monorepo &&
>   sl subtree merge \
>     --url https://git.example.com/lib.git \
>     -r "$(git ls-remote https://git.example.com/lib.git main | cut -f1)" \
>     --to-path vendor/lib
using cached git repo at $COMPARISON/home/.sl_cache/gitrepos/316067af85b8bd24e96f811d9f55a8f2d20eed8dcae7796fe42d9eb9ea621a17
pulling 'd9ba6ce5226d361edcb97b2be461681c61e9006b' from 'https://git.example.com/lib.git'
searching for merge base ...
found the last subtree cross-repo merge commit b41e133c9846
merge base: 9a471d297ba8
update complete
(subtree merge, don't forget to commit)
```

```scrut
$ ls vendor/lib/src
compat.txt
parse.txt
```

A plain `git rebase` drops the header too, since it writes new commits
with the standard fields only. Sapling's own rewrites, such as `sl fold`,
carry the record along.

### With `git-splice`: the file goes

`git-splice` merges from the release that `.splice` names, 1.4:

```scrut
$ cd ../splice-monorepo && git splice pull vendor/lib
ok   vendor/lib fetched (main moved 9a471d2..d9ba6ce)
ok   vendor/lib: pulled d9ba6ce
```

```scrut
$ ls vendor/lib/src
parse.txt
```

## Branch a folder

Directory branching inside one repository is what `sl subtree` is built
for. First, `sl goto --clean` drops the merge above. Sapling wants to
branch from a public commit, one that's pushed. This monorepo has no
remote, so it allows any commit:

```scrut
$ cd ../monorepo &&
>   sl goto -q --clean . &&
>   sl config --local subtree.allow-any-source-commit true
updated config in $COMPARISON/monorepo/.git/sl/config
```

`copy` branches a folder into another, and `merge` later brings the
original's changes over:

```scrut
$ sl subtree copy --from-path app --to-path app-stable -m "branch app-stable" >/dev/null &&
>   echo "new feature" >>app/main.txt &&
>   git commit -q -a -m "app: new feature"
```

```scrut
$ sl subtree merge --from-path app --to-path app-stable
searching for merge base ...
found the last subtree copy commit 4d16a253cb0e
merge base: 289ff1b89a63
update complete
(subtree merge, don't forget to commit)
```

```scrut
$ tail -n 1 app-stable/main.txt
new feature
```

### With `git-splice`: no equivalent

A splice is a folder with a repository of its own. Two folders of one monorepo, merged into each other, are
Sapling's case.

## `git-splice` next to `sl`

`sl` works in the Git repository, so `git-splice` can run in the same
one. A commit with `sl` keeps Git on its branch:

```scrut
$ cd ../splice-monorepo &&
>   echo "fix" >>vendor/lib/src/parse.txt &&
>   sl commit -q -m "fix parse() again" &&
>   git status | head -n 1
On branch main
```

```scrut
$ git splice status
On branch main

  ahead 5  vendor/lib
```

`sl amend` leaves Git's index behind: Git still has the file as it was
before the amend, staged:

```scrut
$ echo "more" >>vendor/lib/src/parse.txt && sl amend -q && git status --short
MM vendor/lib/src/parse.txt
```

```scrut
$ git splice push vendor/lib
??   vendor/lib: uncommitted changes aren't pushed -- commit them first
ok   vendor/lib: pushed 2394809 to main
```

The push sends the amended commit, but warns about changes that aren't
there.

`git reset` brings the index back to the commit:

```scrut
$ git reset -q && git status --short
```

`sl goto` moves to another commit with a detached `HEAD`, where
`git-splice` stops, as it does in a
[jj repository](02-jj.md#git-splice-stops-at-the-detached-head):

```scrut
$ sl prev -q && git splice status
[346c47] splice: pull vendor/lib from main at d9ba6ce
!!   not on a branch (detached HEAD) -- git splice requires a named branch
[1]
```

`git checkout` puts Git back on the branch:

```scrut
$ git checkout -q main && git splice status
On branch main

  up to date  vendor/lib
```
