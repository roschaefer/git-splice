# status

`git splice status [--upstream <name>] [--base <branch>] [path…]`

Lists every splice: a folder with a `.splice` file. Each one gets its sync
state, with commits counted like `git status` counts them against a
tracking branch: "behind 1" is one commit for `pull` to bring in.
`status` doesn't fetch; it uses what was fetched last.

<!-- Builds a fresh sandbox; see `just docs-check`.
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/scrut-setup.sh"
```
-->

In the [sandbox](sandbox.md), `vendor/pkg-a`'s upstream has one commit the
monorepo doesn't have yet:

```scrut
$ git splice status
On branch main

  behind 1  vendor/pkg-a
```

## Sync states

`status` reports one of these states for each splice, and `merge`, `pull`
and `push` act on it. Each example is a small, tested scenario;
[all scenarios](../scenarios/README.md) cover more situations.
`status` lists the splices that need something first, most urgent first,
as in [this monorepo with many splices](../scenarios/many-splices/README.md).

| `status` shows | Meaning | What to do |
| --- | --- | --- |
| `?? never fetched` | The upstream wasn't fetched in this clone yet. ([example](../scenarios/never-fetched/README.md)) | Run `git splice fetch`. |
| `up to date` | Both sides are the same. ([example](../scenarios/up-to-date/README.md)) | Nothing to do. |
| `ahead N` | Only your side changed. ([example](../scenarios/up-to-date/push-ahead/README.md)) | Run `git splice push`. |
| `behind N` | Only the upstream changed. ([example](../scenarios/up-to-date/pull-ahead/README.md)) | Run `git splice pull`. |
| `ahead N, behind M` | Both sides changed since they last matched. ([example](../scenarios/up-to-date/push-ahead/diverged-common-ancestor/README.md)) | Run `git splice pull`, then `push`. On a conflict, resolve it and `git commit` first. |
| `!! unrelated history` | Both sides changed and share no history, e.g. the upstream was rebuilt from scratch. ([example](../scenarios/up-to-date/push-ahead/diverged-unrelated-history/README.md)) | Pick a side. `merge`, `pull` and `push` refuse to guess and print the commands to keep either side, or both. |
| `unchanged, no upstream branch` or `new, ahead N` | The upstream has no branch with your branch's name. The splice is unchanged since the base branch, or changed on this branch. ([unchanged](../scenarios/up-to-date/feature-branch-unchanged/README.md), [changed](../scenarios/up-to-date/feature-branch-unchanged/feature-branch-changed/README.md)) | Run `git splice push`. It creates the branch only if the splice changed. |

## The `.splice` file

The `.splice` file names the upstream, and the upstream commit the folder
last matched. That's all the state there is:

```scrut
$ git config --file vendor/pkg-a/.splice --list
splice.id=679c78b9916de804
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
the [design](../../docs/design/README.md#vocabulary) and explained in the
[sync model](../concepts/sync-model/README.md). One lives in the
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
marks R's commits that T lacks, `>` T's commits that R lacks. Since B, no
commit changed the folder, so R has nothing to add to U: R = U. U is an
ancestor of T, so `status` shows `behind 1`, the commit between them.

B is the newest commit that changed `.splice`, what
[`boundary`](boundary.md) prints:

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

T is the fetched branch. Its history leads to U:

```scrut
$ git log --oneline splices/pkg-a/main
703b936 pkg-a: a second commit, after the clone
9bb866a pkg-a: seed
```

R is what [`rebuild`](rebuild.md) prints. `log --graph` draws it together
with T, labeled, down to the commit they build on, `o`. Here, that's R
itself:

```scrut
$ git splice log --graph vendor/pkg-a
===  vendor/pkg-a (main)
> 703b936 (T) pkg-a: a second commit, after the clone  (Walkthrough <walkthrough@example.com>)
o 9bb866a (R) pkg-a: seed  (Walkthrough <walkthrough@example.com>)
```
