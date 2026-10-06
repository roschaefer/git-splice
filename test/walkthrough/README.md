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
[sync state](../../docs/sync-states.md), with commits counted like
`git status` counts them against a tracking branch: "behind 1" is one
commit for `pull` to bring in. `status` doesn't fetch; it uses what was
fetched last.

```scrut
$ git splice status
ok   vendor/pkg-a -> main (pull: behind 1)
```

The `.splice` file names the upstream, and the upstream commit the folder
last matched. That's all the state there is:

```scrut
$ git config --file vendor/pkg-a/.splice --list
splice.commit=9bb866a3ba726f2229597a45e8ea3368f7e669a8
upstream.origin.url=https://git.example.com/pkg-a.git
```

There's no Git remote, so nothing can push the monorepo to an upstream by
mistake:

```scrut
$ git remote
```

## B, U, T and R

Every command works a splice's state out from four commits, named as in
the [design](../../docs/design/README.md#vocabulary). One lives in the
monorepo's history, two in the upstream's, and one is computed:

| | Commit | Lives in |
|---|---|---|
| **B** | The boundary: the newest commit on the monorepo's first-parent history that changed `.splice`. | the monorepo |
| **U** | The synced commit: the upstream commit `.splice` records at B. | the upstream |
| **T** | *Theirs*: the upstream branch as the monorepo last saw it, in `refs/splices/`. | the upstream |
| **R** | The rebuild, *ours*: the splice's changes in the monorepo, rebuilt as upstream commits. What `push` sends ([how](../../docs/design/README.md#splicing-out-push-and-the-rebuild)). | computed |

For `vendor/pkg-a` in the sandbox:

```text
      monorepo, newest first                 pkg-a.git, newest first

      . lib-c: first version             T   > pkg-a: a second commit, after the clone
  B   = splice: clone vendor/pkg-a           |
          (folder = U)                 U = R * pkg-a: seed
```

On the left, as in the [README](../../README.md#the-solution), `=` marks
the commits that change `.splice`, `*` those that change other files in
the folder, whether or not they change files elsewhere too, and `.` those
that don't touch the folder. On the right, as in `git splice log`, `<`
marks R's commits that T lacks, `>` T's commits that R lacks, and `*` the
commits both have. Since B, no
commit changed the folder, so R has nothing to add to U: R = U. U is an
ancestor of T, so the state is `pull: behind 1`, the commit between them.

B is the newest commit that changed `.splice`:

```scrut
$ git log --first-parent -1 --oneline -- vendor/pkg-a/.splice
7b30b50 splice: clone vendor/pkg-a from main at 9bb866a
```

U is the commit recorded there. `fetch` copied it into the monorepo, so
Git can show it:

```scrut
$ git log -1 --oneline "$(git config --file vendor/pkg-a/.splice splice.commit)"
9bb866a pkg-a: seed
```

T is the fetched branch. Its history leads to U:

```scrut
$ git log --oneline splices/pkg-a/main
703b936 pkg-a: a second commit, after the clone
9bb866a pkg-a: seed
```

R has no command of its own yet
([#54](https://github.com/roschaefer/git-splice/issues/54)), but
`log --graph` draws it together with T, labeled, down to the commit they
build on, `o`. Here, that's R itself:

```scrut
$ git splice log --graph vendor/pkg-a
===  vendor/pkg-a (main)
> 703b936 (T) pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
o 9bb866a (R) pkg-a: seed  (Walkthrough <walkthrough@example.com>)
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
for what a pull brings in, `<` for what a push publishes. `--graph` draws
them as a graph, as [above](#b-u-t-and-r).

```scrut
$ git splice log
===  vendor/pkg-a (main)
> 703b936 pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
===  vendor/pkg-b (main)
> b937c4f pkg-b: add a feature  (Walkthrough <walkthrough@example.com>)
```

## Looking at an upstream

`fetch` keeps each upstream's complete history in the monorepo, under
`refs/splices/<key>/<branch>`, where the key is the upstream's short name
in this repository, from its URL: `https://git.example.com/pkg-b.git`
gets `pkg-b`.
Every Git command reads it as `splices/<key>/<branch>`, so there's
nothing to clone:

```scrut
$ git log --oneline splices/pkg-b/main
b937c4f pkg-b: add a feature
9b3cb02 pkg-b: seed
```

```scrut
$ git show splices/pkg-b/main:file.txt
pkg-b: seed
pkg-b: add a feature
```

For a checkout of the upstream, without a network round trip, add a
worktree, and remove it when you're done. Commits made there don't reach
upstream; changes belong in the monorepo, and `push` publishes them.

```scrut
$ git worktree add -q --detach ../pkg-b-upstream splices/pkg-b/main && ls ../pkg-b-upstream
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

The commit `merge` made is `vendor/pkg-a`'s new B, and its `.splice` records T
as the new U:

```scrut
$ git config --file vendor/pkg-a/.splice splice.commit
703b9360f7ac335a1134e9b5771a90a7c09ba39a
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
e49a1ae splice: pull vendor/pkg-b from main at b937c4f
04198c1 splice: merge vendor/pkg-a from main at 703b936
621efe6 splice: clone vendor/pkg-b from main at 9b3cb02
ceb41dd lib-c: first version
7b30b50 splice: clone vendor/pkg-a from main at 9bb866a
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
ok   vendor/pkg-a -> main (push: ahead 1)
```

Now R has a commit of its own: the local fix, rebuilt on top of U:

```text
      monorepo, newest first                 pkg-a.git, newest first

      * pkg-a: a local fix               R   < pkg-a: a local fix
      . splice: pull vendor/pkg-b            |
  B   = splice: merge vendor/pkg-a           |
          (folder = U)                 U = T * pkg-a: a second commit, after the clone
                                             * pkg-a: seed
```

T is an ancestor of R, so the state is `push: ahead 1`.

`diff` shows what `push` would send, the changes from T to R, with paths
as the upstream sees them.

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

`--stat` summarizes the changes per file:

```scrut
$ git splice diff --stat
===  vendor/pkg-a
 file.txt | 1 +
 1 file changed, 1 insertion(+)
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

`push` updates T too, so now T = R. B and U stay where they were: a push
writes nothing to the monorepo.

```scrut
$ git log -1 --oneline splices/pkg-a/main
2d02eb8 pkg-a: a local fix
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
