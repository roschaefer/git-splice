# `git submodule` compared

A submodule keeps the library in its own repository, nested in the
monorepo's worktree. The monorepo commits only the library's URL, in
`.gitmodules`, and one of its commits, as a "gitlink". This page shows
what that boundary means when you fix the library together with your app,
and in a second worktree. It ends with what submodules do better.

The setup: `https://git.example.com/lib.git`, a library with 30 commits,
and a monorepo with an app. [How these pages run](README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

```scrut
$ git submodule add -q https://git.example.com/lib.git vendor/lib && git commit -q -m "add lib as a submodule"
```

## The monorepo doesn't see the library's files

You fix the library and use the fix in the app, in one go:

```scrut
$ echo "fix" >>vendor/lib/src/parse.txt && echo "call parse()" >>app/main.txt
```

`status` names the changed app file, but only the submodule, not the file
in it:

```scrut
$ git status --short
 M app/main.txt
 m vendor/lib
```

`diff` shows the app's change and, for the library, only that the
submodule's checkout is dirty:

```scrut
$ git diff --stat
 app/main.txt | 1 +
 vendor/lib   | 0
 2 files changed, 1 insertion(+)
```

```scrut
$ git diff -- vendor/lib
diff --git a/vendor/lib b/vendor/lib
--- a/vendor/lib
+++ b/vendor/lib
@@ -1 +1 @@
-Subproject commit bafd496b1f4512a95b69464604f3da428aa9e33b
+Subproject commit bafd496b1f4512a95b69464604f3da428aa9e33b-dirty
```

To be fair, Git can look inside when asked:

```scrut
$ git diff --submodule=diff -- vendor/lib
Submodule vendor/lib contains modified content
diff --git a/vendor/lib/src/parse.txt b/vendor/lib/src/parse.txt
index ac9837c..66931ff 100644
--- a/vendor/lib/src/parse.txt
+++ b/vendor/lib/src/parse.txt
@@ -28,3 +28,4 @@ line 27
 line 28
 line 29
 line 30
+fix
```

Committing takes two commits, in two repositories. The monorepo's commit
records only that the gitlink moved:

```scrut
$ git -C vendor/lib commit -q -a -m "fix parse()" && git commit -q -a -m "app: call parse()"
```

```scrut
$ git show --stat --format=%s
app: call parse()

 app/main.txt | 1 +
 vendor/lib   | 2 +-
 2 files changed, 2 insertions(+), 1 deletion(-)
```

So the monorepo's history of a library file is empty, and its search
doesn't find the fix unless asked to recurse:

```scrut
$ git log --oneline -- vendor/lib/src/parse.txt
```

Only the patches of commits that moved the gitlink can show what changed
inside, with `--submodule=diff` again:

```scrut
$ git log -1 -p --submodule=diff --format=%s -- vendor/lib
app: call parse()

Submodule vendor/lib bafd496..a6152f5:
diff --git a/vendor/lib/src/parse.txt b/vendor/lib/src/parse.txt
index ac9837c..66931ff 100644
--- a/vendor/lib/src/parse.txt
+++ b/vendor/lib/src/parse.txt
@@ -28,3 +28,4 @@ line 27
 line 28
 line 29
 line 30
+fix
```

`status` has no such option. It never names a file inside a submodule,
as above, and rejects `--recurse-submodules`:

```scrut
$ git status --recurse-submodules | head -1
error: unknown option `recurse-submodules'
```

```scrut
$ git grep -c fix -- vendor/lib; git grep -c --recurse-submodules fix -- vendor/lib
vendor/lib/src/parse.txt:1
```

The same fix in a splice is one ordinary commit, and every command sees
the file. Here in a copy of the monorepo from before the submodule:

```scrut
$ cd ../splice-monorepo && git splice clone https://git.example.com/lib.git vendor/lib
===  vendor/lib: fetching https://git.example.com/lib.git
ok   vendor/lib: cloned bafd496 from main
```

```scrut
$ echo "fix" >>vendor/lib/src/parse.txt && echo "call parse()" >>app/main.txt && git status --short
 M app/main.txt
 M vendor/lib/src/parse.txt
```

```scrut
$ git commit -q -a -m "fix parse() and call it" && git show --stat --format=%s
fix parse() and call it

 app/main.txt             | 1 +
 vendor/lib/src/parse.txt | 1 +
 2 files changed, 2 insertions(+)
```

```scrut
$ git log --oneline -- vendor/lib/src/parse.txt
7c6f5f0 fix parse() and call it
e943000 splice: clone vendor/lib from main at bafd496
```

```scrut
$ cd ../monorepo
```

## Two repositories, two pushes, in the right order

The monorepo's commit points at a library commit that only exists in this
clone. Push the monorepo first, and colleagues get a commit they can't
check out:

```scrut
$ git clone -q --bare --no-local . ../origin.git && git clone -q --recurse-submodules ../origin.git ../colleague
fatal: git upload-pack: not our ref a6152f5cee8b2bfd6b5dfc7bbb2bf5d8a7562325
fatal: remote error: upload-pack: not our ref a6152f5cee8b2bfd6b5dfc7bbb2bf5d8a7562325
fatal: Fetched in submodule path 'vendor/lib', but it did not contain a6152f5cee8b2bfd6b5dfc7bbb2bf5d8a7562325. Direct fetching of that commit failed.
[128]
```

The library's commit has to be pushed first:

```scrut
$ git -C vendor/lib push -q && rm -rf ../colleague && git clone -q --recurse-submodules ../origin.git ../colleague && echo cloned
cloned
```

Here the submodule was on `main`, because `git submodule add` cloned it.
In the colleague's clone, `git submodule update` checked out the
monorepo's recorded commit, on no branch. A fix committed there needs a
branch first (`git switch -c`), or a push as `HEAD:<branch>`:

```scrut
$ git -C ../colleague/vendor/lib status --short --branch
## HEAD (no branch)
```

A splice's files are part of the monorepo commit, so a colleague's clone
is complete whether or not the fix reached the library yet. Pushing it
there is a separate step, `git splice push`, for when the fix is ready.

## A second worktree

`git worktree add` checks out another branch next to this one. The
submodule stays empty there:

```scrut
$ git worktree add -q ../feature -b feature && ls -A ../feature/vendor/lib
```

```scrut
$ git -C ../feature submodule status
-a6152f5cee8b2bfd6b5dfc7bbb2bf5d8a7562325 vendor/lib
```

Each worktree initializes its submodules on its own, with its own clone of
the library, under `.git/worktrees/<name>/modules/`:

```scrut
$ git -C ../feature submodule update -q --init && cat ../feature/vendor/lib/.git
gitdir: ../../../monorepo/.git/worktrees/feature/modules/vendor/lib
```

The submodule's own repository, with its own `.git/config`, is separate
in each worktree. But the monorepo's settings for the submodule,
`submodule.<name>.*` like its URL, live in the monorepo's `.git/config`,
which all worktrees share. A change in one worktree changes the others:

```scrut
$ git -C ../feature config submodule.vendor/lib.url https://git.example.com/lib-fork.git && git config submodule.vendor/lib.url
https://git.example.com/lib-fork.git
```

```scrut
$ git config submodule.vendor/lib.url https://git.example.com/lib.git
```

And Git refuses to move a worktree that has submodules, and removes it
only with `--force`:

```scrut
$ git worktree move ../feature ../feature-2
fatal: working trees containing submodules cannot be moved or removed
[128]
```

```scrut
$ git worktree remove ../feature
fatal: working trees containing submodules cannot be moved or removed
[128]
```

```scrut
$ git worktree remove --force ../feature && echo removed
removed
```

Git's documentation says so too: "Multiple checkout in general is still
experimental, and the support for submodules is incomplete. It is NOT
recommended to make multiple checkouts of a superproject."
([`git worktree`, BUGS](https://git-scm.com/docs/git-worktree#_bugs))

A splice lives in the worktree. A new worktree has it, with nothing to
initialize:

```scrut
$ cd ../splice-monorepo && git worktree add -q ../splice-feature -b feature && cd ../splice-feature && git splice status
ok   vendor/lib -> feature (upstream has no such branch; unchanged since 'main')
```

What git-splice keeps outside the worktree, the fetched upstream
branches under `refs/splices/`, is shared by all worktrees, like
`refs/remotes/`: it describes the upstream, which is the same from every
worktree. A push from one worktree is seen by the others:

```scrut
$ echo "fix 2" >>vendor/lib/src/parse.txt && git commit -q -a -m "fix 2" && git splice push vendor/lib
??   vendor/lib: upstream has no 'feature' branch yet -- this push creates it (changed since 'main')
ok   vendor/lib: pushed 6b3df25 to feature
```

```scrut
$ cd ../splice-monorepo && git for-each-ref --format='%(refname)' refs/splices
refs/splices/lib/feature
refs/splices/lib/main
```

```scrut
$ git worktree remove ../splice-feature && echo removed
removed
```

One limit: two fetches at the same time, in two worktrees, may both try to
move the same ref. Then one fails with `cannot lock ref`, and running it
again fixes it, as with two `git fetch` at once.

## Where submodules are better

- **The library's files stay out of the monorepo's history.** A clone
  that doesn't need them, `git clone` without `--recurse-submodules`,
  doesn't download them. A splice's files are monorepo content, in every
  clone.
- **The commit pins an exact upstream revision.** A splice's commit is
  where it last matched upstream; the folder may have changed since.
- **Access stays separate.** The library can be private while the
  monorepo isn't, or the other way round.
- **Settings can be overridden per clone.** Pointing a submodule at a
  mirror or fork takes a `git config` change, not a commit. A splice's URL
  is committed in `.splice`, but `url.<base>.insteadOf` overrides it the
  same way, without a commit, as these pages do to reach
  `https://git.example.com/` on this machine:

```scrut
$ git config --get-regexp 'url\..*insteadof'
url.$COMPARISON/upstream/.insteadof https://git.example.com/
```
