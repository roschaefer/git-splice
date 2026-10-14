# Sync model

A splice's folder has two histories: the monorepo's, where it's a
folder, and its upstream's, where it's the whole repository. Commits
don't cross between them, changes do. Every command works out what to
cross from five commits:

| | Commit | Lives in |
|---|---|---|
| **B** | The boundary, where the rebuild starts: on the monorepo's first-parent history, the newest commit that changed `.splice` and whose folder is the upstream commit it recorded. Usually the last pull. Where the splice starts, the mount (its first `.splice`, or a `git mv`), B is that commit whatever its folder, and the rebuild copies B too where its folder isn't S, e.g. after `init`, or a `git mv` with unpushed changes. For a nested splice, the last pull of the splice above can be B ([nesting](../nesting/README.md)). | the monorepo |
| **U** | The synced commit, U(H): the upstream commit `.splice` records at HEAD, the last one pulled. | the upstream |
| **S** | The start, U(B): the upstream commit B's `.splice` records, and B's folder. R starts on it. Usually U. | the upstream |
| **T** | *Theirs*: the upstream branch as the monorepo last saw it, in `refs/splices/`. | the upstream |
| **R** | The rebuild, *ours*: the folder's history since B, rebuilt as upstream commits on top of S, and merged with U(X) for each pull X since that merged unpushed commits. | computed |

For a nested splice, R's history up to the last pull of the splice above
comes from the upstream above, at its synced commit
([nesting](../nesting/README.md)).

Every commit X that changed `.splice` records an upstream commit, its
sync point **U(X)**: what `git config --blob X:path/.splice splice.commit`
prints. U and S are two of them, at H and at B. Between B and H, each
pull X has its own U(X), and the pull before it, X^, had U(X^): the
synced commits before and after X.

U and T may be missing: right after `init`, there's no U yet, and R
starts as a root commit; before the first fetch, there's no T, and the
splice is *never fetched*, or the upstream has *no such branch*.

[Output](#output) shows the Git commands that find each of them.

A pull could have been a merge, with U as its second parent:
[weak parents](../../../docs/going-forward/weak-parents.md) compares the two.

## R, the rebuild

The monorepo's commits that changed the folder are the splice's own
changes, but they have the monorepo's layout and the monorepo's history.
R copies each of them, since B, as an upstream commit: the folder's tree
without `.splice`, the same author, dates and message, on top of U.

<div align="center">

![Monorepo commits a to d, upstream commits k to n, and the rebuilt commits b+ and d+ on top of U](../../scenarios/sync-model/before-pull.drawio.svg)

</div>

Circles are commits, boxes point at them, newest on top. In the
monorepo, a to d, H is `HEAD`, and B is a: the commit that wrote U into
`path/.splice`, with U as its folder. b and d change the folder, c
changes only other files.
In the upstream, U is k, and so is S, the commit B records. T has moved
on to n.

The rebuild copies the commits in `B..H`, b to d, on top of S. c didn't
touch `path/`, so it's skipped, and b and d become b+ and d+, dashed
because they exist only as the rebuild. A `+` marks a commit rebuilt. Their tip is R. B itself isn't
copied, since its folder is S already.

<div align="center">

![The same graphs after a pull: the pull commit e records n as U, B stays at a with k as S, and R is e+, a merge of the rebuilt d+ and n](../../scenarios/sync-model/after-pull/after-pull.drawio.svg)

</div>

The same splice after `git splice pull`. The pull commit e merged T into
the folder and wrote n into `path/.splice`: U is n now. But b and d were
never pushed, so the upstream still lacks their changes, and e's folder
isn't n. If the rebuild started at e, b and d would reach the upstream as
one lump, under e's message. So B stays a, the newest commit that changed
`.splice` and has the commit it recorded, k, as its folder. k is S, and
no longer U.

From B, R keeps b and d as the commits they were: b+ and d+ on S. Then
it copies e as e+, a merge of d+ and n, as `git pull` would have: e's
folder and message, with d+ and n as parents. Nothing points at b and d, but e is
their descendant
([scenario](../../scenarios/sync-model/after-pull/README.md)).

A `git splice push` then sends b+, d+ and e+, and moves T to e+, a
fast-forward. U stays n, B stays a, and S stays k: a pull right after the
push has nothing to bring in, and only [`git splice pull --bump`](../../walkthrough/bump.md)
records e+ as U, in a commit whose folder is e+. So that commit is the
new B, and e+ is S as well as U.

### Pulls in between

Between B and H, every commit that changed `.splice` differs from the
commit it recorded, or it would be B. The rebuild copies each of them
with that folder, and picks its parents from two commits: what the
rebuild has so far, *before*, and the commit it recorded, U(X):

| *before* and U(X) | The copy's parents | When |
|---|---|---|
| neither contains the other | *before*, then U(X): a merge | a pull merged unpushed commits, as e and e+ above ([scenario](../../scenarios/sync-model/after-pull/README.md)) |
| U(X) contains *before*, or there's no *before* | U(X) | a squash merge put local edits into the pull commit itself ([scenario](../../scenarios/up-to-date/squash-merged-pull/local-edit-in-the-squash/README.md)), or the commit is where the splice starts, e.g. a `git mv` ([scenario](../../scenarios/up-to-date/push-ahead/moved-with-unpushed-commits/README.md)) |
| *before* contains U(X) | *before*, and no copy if the folder didn't change | a hand edit of `.splice`, or a bump while commits are unpushed ([scenario](../../scenarios/up-to-date/push-ahead/pushed-then-pulled/bump-after-push.md#a-bump-while-ahead)) |

So each pull since B that merged unpushed commits adds one merge to R,
with the commit it pulled as the second parent. R takes that commit from
the pull's `.splice`, not from T: T may have moved on since, with a
fetch, and the merge would then claim changes the pull never brought in.

R is never stored. It's computed from `HEAD` each time, and the same
`HEAD` always gives the same R. So a commit pushed once is rebuilt
identically, and the next push is a fast-forward. And since R is
computed, `.splice` needs no monorepo commit ids, which a rebase or a
squash merge would invalidate
([design](../../../docs/design/README.md#splicing-out-push-and-the-rebuild)).

## Three ways, both directions

R and T are two histories of the same folder, as upstream commits. How
they relate is the [sync state](../../walkthrough/status.md#sync-states):

| R and T | State | What crosses |
|---|---|---|
| the same files, or the same commit | up to date | nothing |
| T is an ancestor of R | push | `push` sends R, a fast-forward |
| R is an ancestor of T | pull | `pull` merges T in |
| neither, but with a common ancestor | diverged | `pull` merges T in, then `push` sends R |
| no common ancestor | unrelated history | nothing: `pull` and `push` refuse, and print the commands to keep either side, or both |

A pull is a **three-way merge**, in the monorepo's layout:

- **base**: the newest commit R and T have in common, `git merge-base R T`
- **ours**: `HEAD`, with the folder as it is
- **theirs**: `HEAD` with T's files in the folder

Git merges them as usual. Only the folder differs between base and
theirs, so only the folder can conflict. The result is one ordinary
monorepo commit, which records T as the new U. It's the new B too,
unless it merged commits that were never pushed.

The base is usually U. After a push, it's the pushed commit: R contains
it, so the merge doesn't replay changes the upstream already has. That's
also why U alone says little about where a splice stands. A push moves
T, and with it R's relation to T, but not U.

## Why a push isn't recorded

A push never writes to the monorepo, so U stays what the last pull
brought in. Recording the push would take a monorepo commit that changes
`.splice`, on the branch that pushed. Merging that branch would then
carry the record to a branch that syncs with a different upstream
branch: a feature branch's `.splice` would name a commit of the
upstream's feature branch, and after the merge, `main`'s would too.

It isn't needed either. `status` compares the folder's files with T, and
after the push they're the same, so the splice is up to date. And a pull
merges from where R and T meet, not from U. The rebuild is
deterministic, so R contains the pushed commit, with the same hash, and
they meet there ([example](../../scenarios/up-to-date/push-ahead/pushed-then-pulled/README.md)).
Except after `git splice push --rebuilt-commit`: R doesn't contain an
edited commit, so `git splice pull --bump` has to record it as U before
the next change, as `push` reminds you
([edited-before-push](../../scenarios/up-to-date/push-ahead/edited-before-push/README.md)).

The cost is that each rebuild walks every commit since B, pushed or not.
[Bumping](../../walkthrough/bump.md) records the pushed commit as U where
that matters.

## Output

The walkthrough's [sandbox](../../../docs/sandbox.md), where
`vendor/pkg-a/` is behind its upstream by one commit.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../walkthrough/scrut-setup.sh"
```
-->

For `vendor/pkg-a/`:

```text
      monorepo, newest first                 pkg-a.git, newest first

      . lib-c: first version             T   > pkg-a: a second commit, after the clone
  B   = splice: clone vendor/pkg-a           |
          (folder = U)                 U = R * pkg-a: seed
```

On the left, as in the [README](../../../README.md#the-solution), `=` marks
the commits that change `.splice`, `*` those that change other files in
the folder, whether or not they change files elsewhere too, and `.` those
that don't touch the folder. On the right, as in `git splice log`, `<`
marks R's commits that T lacks, `>` T's commits that R lacks. Since B, no
commit changed the folder, so R has nothing to add to U: R = U. U is an
ancestor of T, so `status` shows `behind 1`, the commit between them.

B is what [`boundary`](../../walkthrough/boundary.md) prints. Here,
it's the newest commit that changed `.splice`:

```scrut
$ git log --first-parent -1 --oneline -- vendor/pkg-a/.splice
3aef6fd splice: clone vendor/pkg-a from main at 9bb866a
```

U is the commit recorded there. `fetch` copied it into the monorepo, so
Git can show it:

```scrut
$ git log -1 --oneline "$(git config --file vendor/pkg-a/.splice splice.commit)"
9bb866a pkg-a: seed
```

Its folder is U, so it's B, and U is S, where R starts:

```scrut
$ git diff --quiet "$(git config --file vendor/pkg-a/.splice splice.commit)" "$(git log --first-parent -1 --format=%H -- vendor/pkg-a/.splice):vendor/pkg-a" -- ':!.splice' && echo "B's folder is U"
B's folder is U
```

T is the fetched branch. Its history leads to U:

```scrut
$ git log --oneline splices/pkg-a/main
703b936 pkg-a: a second commit, after the clone
9bb866a pkg-a: seed
```

R is what [`rebuild`](../../walkthrough/rebuild.md) prints, and
`log --graph` draws it and T, labeled, down to the commit they have in
common, `o`. Nothing changed the folder since B, so R is U:

```scrut
$ git splice log --graph vendor/pkg-a
===  vendor/pkg-a (main)
> 703b936 (T) pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
o 9bb866a (R) pkg-a: seed  (Walkthrough <walkthrough@example.com>)
```

A change in the monorepo, to a file the upstream didn't change:

```scrut
$ echo "local" >vendor/pkg-a/local.txt && git add vendor/pkg-a/local.txt && git commit -q -m "pkg-a: a local file"
```

Now R has a commit T lacks, and the other way around:

```scrut
$ git splice status vendor/pkg-a
On branch main

  ahead 1, behind 1  vendor/pkg-a
```

```scrut
$ git splice log --graph vendor/pkg-a
===  vendor/pkg-a (main)
< f985b9f (R) pkg-a: a local file  (Walkthrough <walkthrough@example.com>)
| > 703b936 (T) pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
|/  
o 9bb866a pkg-a: seed  (Walkthrough <walkthrough@example.com>)
```

The pull merges T in, with `o` as the base:

```scrut
$ git splice pull vendor/pkg-a
ok   vendor/pkg-a fetched
ok   vendor/pkg-a: pulled 703b936
```

The pull commit records T as U. Its folder isn't T's tree, since it has
the local file too, so it isn't the new B: B stays the clone, and S its synced commit,
`pkg-a: seed`,

```scrut
$ git log -1 --format=%s "$(git splice boundary vendor/pkg-a)"
splice: clone vendor/pkg-a from main at 9bb866a
```

and R joins the local commit with T by a merge, as `git pull` would have:

```scrut
$ git splice log --graph vendor/pkg-a
===  vendor/pkg-a (main)
<   6dc0e40 (R) splice: pull vendor/pkg-a from main at 703b936  (Walkthrough <walkthrough@example.com>)
|\  
< | f985b9f pkg-a: a local file  (Walkthrough <walkthrough@example.com>)
| o 703b936 (T) pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
|/  
o 9bb866a pkg-a: seed  (Walkthrough <walkthrough@example.com>)
```

The push sends R, a fast-forward of T:

```scrut
$ git splice push vendor/pkg-a
ok   vendor/pkg-a: pushed 6dc0e40 to main
```

```scrut
$ git log --graph --format='%h %s' splices/pkg-a/main
*   6dc0e40 splice: pull vendor/pkg-a from main at 703b936
|\  
| * 703b936 pkg-a: a second commit, after the clone
* | f985b9f pkg-a: a local file
|/  
* 9bb866a pkg-a: seed
```

Now R and T are equal, and the splice is up to date. U is still the
commit the pull brought in. It lags behind T, since the push didn't
write to the monorepo:

```scrut
$ git splice status vendor/pkg-a
On branch main

  up to date  vendor/pkg-a
```

```scrut
$ git config --file vendor/pkg-a/.splice splice.commit && git rev-parse splices/pkg-a/main
703b9360f7ac335a1134e9b5771a90a7c09ba39a
6dc0e40cd5eda556b7b18759d2e2bb1ae2ae214a
```
