# Walkthrough

`just walkthrough` builds a throwaway monorepo in a temporary directory and
opens a shell in it. This page walks through every command there, in
order, with the output each one prints. CI runs this page with
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

More walkthroughs, each starting from a fresh sandbox:

- [Feature branches](feature-branches.md): the upstream branch follows your
  branch, and `push` creates it only where a splice changed.
- [Diverged history](diverged.md): both sides changed the same line, and
  you resolve the conflict.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

## status

Lists every splice: a folder with a `.splice` file. Each one gets its
[sync state](../README.md#sync-states) and the files that differ. `status`
doesn't fetch; it uses what was fetched last.

```scrut
$ git splice status
ok   vendor/pkg-a -> main (pull)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

The `.splice` file names the upstream, and the upstream commit the folder
last matched. That's all the state there is:

```scrut
$ git config --file vendor/pkg-a/.splice --list
splice.url=https://git.example.com/pkg-a.git
splice.commit=9bb866a3ba726f2229597a45e8ea3368f7e669a8
```

There's no Git remote, so nothing can push the monorepo to an upstream by
mistake:

```scrut
$ git remote
```

## clone

`clone` splices an existing repository into a new folder, as one commit.

```scrut
$ git splice clone https://git.example.com/pkg-b.git vendor/pkg-b
===  vendor/pkg-b: fetching https://git.example.com/pkg-b.git
ok   vendor/pkg-b: cloned 9b3cb02 from main
```

## fetch

Someone pushes to `pkg-b`'s upstream. `fetch` fetches every splice's
upstream in parallel and calls out which branch moved.

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

`log` shows the commits between each splice and its upstream branch: `>`
for what a pull brings in, `<` for what a push publishes.

```scrut
$ git splice log
===  vendor/pkg-a (main)
> 703b936 pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
===  vendor/pkg-b (main)
> b937c4f pkg-b: add a feature  (Walkthrough <walkthrough@example.com>)
```

## Looking at an upstream

`fetch` keeps each upstream's complete history in the monorepo, under
`refs/splices/<path>/<branch>`. Every Git command reads it as
`splices/<path>/<branch>`, so there's nothing to clone:

```scrut
$ git log --oneline splices/vendor/pkg-b/main
b937c4f pkg-b: add a feature
9b3cb02 pkg-b: seed
```

```scrut
$ git show splices/vendor/pkg-b/main:file.txt
pkg-b: seed
pkg-b: add a feature
```

For a checkout of the upstream, without a network round trip, add a
worktree, and remove it when you're done. Commits made there don't reach
upstream; changes belong in the monorepo, and `push` publishes them.

```scrut
$ git worktree add -q --detach ../pkg-b-upstream splices/vendor/pkg-b/main && ls ../pkg-b-upstream
file.txt
```

```scrut
$ git worktree remove ../pkg-b-upstream
```

`git log --all` shows the upstreams' histories too;
`git log --exclude='refs/splices/*' --all` leaves them out.

## merge

`merge` splices in what was fetched, without contacting the upstream, as
one ordinary commit per splice. Commands that change the monorepo or an
upstream name their splices, or take `--all`.

```scrut
$ git splice merge vendor/pkg-a
ok   vendor/pkg-a: merged 703b936
```

## pull

`pull` is `fetch` and `merge` in one: this brings in the `pkg-b` change
fetched above.

```scrut
$ git splice pull --all
ok   vendor/pkg-a fetched
ok   vendor/pkg-b fetched
ok   vendor/pkg-a: nothing to pull
ok   vendor/pkg-b: pulled b937c4f
```

The monorepo's history stays linear. Upstream's commits stay upstream,
and in `refs/splices/`:

```scrut
$ git log --oneline
21e0e5a splice: pull vendor/pkg-b from main at b937c4f
4bc508a splice: merge vendor/pkg-a from main at 703b936
c36e2ef splice: clone vendor/pkg-b from main at 9b3cb02
cf63522 lib-c: first version
c41a285 splice: clone vendor/pkg-a from main at 9bb866a
ebe3b2b initial commit
```

## diff

A commit in the monorepo changes `vendor/pkg-a`, so its state becomes
`push`.

```scrut
$ echo "a local fix" >>vendor/pkg-a/file.txt && git commit -qam "pkg-a: a local fix"
```

```scrut
$ git splice status vendor/pkg-a
ok   vendor/pkg-a -> main (push)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```

`diff` shows what `push` would send, with paths as the upstream sees them.

```scrut
$ git splice diff
===  vendor/pkg-a
diff --git a/file.txt b/file.txt
index 1b6c064..15c0cbd 100644
--- a/file.txt
+++ b/file.txt
@@ -1,2 +1,3 @@
 pkg-a: seed
 pkg-a: a second commit, after the clone
+a local fix
```

## push

`push` rebuilds the commits that changed each splice since the last sync,
without `.splice`, and pushes them to the branch named like yours. It
writes nothing to the monorepo.

```scrut
$ git splice push --all
ok   vendor/pkg-a: pushed 2d02eb8 to main
ok   vendor/pkg-b: nothing to push
```

```scrut
$ git -C "$WALKTHROUGH/upstream/pkg-a.git" log --format=%s main
pkg-a: a local fix
pkg-a: a second commit, after the clone
pkg-a: seed
```

```scrut
$ git splice status
ok   vendor/pkg-a -> main (up to date)
ok   vendor/pkg-b -> main (up to date)
```

## init

`libs/c` grew inside the monorepo. `init` makes it a splice of the new,
empty `lib-c.git`; the first push publishes its history.

```scrut
$ git splice init libs/c https://git.example.com/lib-c.git
ok   libs/c: initialized -- 'git splice push libs/c' publishes it
```

```scrut
$ git splice push libs/c
??   libs/c: upstream has no 'main' branch yet -- this push creates it
ok   libs/c: pushed 57c40bc to main
```

```scrut
$ git -C "$WALKTHROUGH/upstream/lib-c.git" log --format=%s main
lib-c: first version
```
