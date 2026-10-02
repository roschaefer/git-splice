# git-splice: design

`git splice` keeps folders of a monorepo in sync with their own upstream
repositories, in both directions. It's the successor of `git-subtrees`, and
it follows the same core idea: switching branches in the monorepo switches
the branch every folder syncs with. Unlike `git-subtrees`, it doesn't use
`git subtree` or Git remotes.

This page records the decisions made before writing the code. Two
prototypes in this folder show the core mechanisms working:

- [`pull-prototype.sh`](pull-prototype.sh): a pull as one ordinary commit,
  with normal conflict handling.
- [`rebuild-prototype.sh`](rebuild-prototype.sh): the history a push sends,
  compared with `git subtree split`.

## Why not keep building on `git subtree`

`git-subtrees` ran into four problems that all come from `git subtree`:

1. **Slow `status`** ([#30](https://github.com/roschaefer/git-subtrees/issues/30)).
   `git subtree split` walks the monorepo's whole history for every changed
   folder. Only a `--rejoin` merge lets it skip history.
2. **Publishing the monorepo by accident**
   ([#50](https://github.com/roschaefer/git-subtrees/issues/50)). A subtree
   is a Git remote, and a remote stands for a whole repository. A plain
   `git push`, an IDE's sync button or `push.autoSetupRemote` can send the
   whole monorepo there.
3. **The shape of history.** Every `git subtree pull --squash` adds two
   commits: an orphan squash commit and a merge. The monorepo's history
   can't stay linear.
4. **Squash merges lose the sync point.** The squash commit is only
   reachable through the merge's second parent. When a branch that pulled
   gets squash-merged, `main` loses it. `status` then reports `diverged` for a
   purely local change, and after the recovery pull, the push sends a
   duplicate of an upstream commit upstream.

[git-subrepo](https://github.com/ingydotnet/git-subrepo) solves 1 to 3 with
a committed state file, fetching by URL and one commit per pull. Building
on it isn't an option:

- It records a monorepo SHA (`parent`) in that file, so squash merges and
  rebases break it. Upstream issues #464, #539, #600 and #617 have been open
  for years.
- It fixes each folder to one upstream branch, so it doesn't follow the
  monorepo's branches.
- Its push rebuild uses the current date for the committer, so it isn't
  deterministic (subrepo#670).

`git splice` takes subrepo's architecture and fixes those three points.

## Vocabulary

| Term | Meaning |
|---|---|
| **splice** | A folder of the monorepo that has its own upstream repository: "`vendor/a` is spliced in from `github.com/x/a`", "the `vendor/a` splice". |
| **path** | Where the splice lives in the monorepo, e.g. `vendor/a`. (`git subtree` calls it `--prefix`.) |
| **upstream** | The splice's own repository, given by URL. |
| **synced commit** (U) | The upstream commit whose content the splice last matched, recorded in `.splice`. |
| **boundary** (B) | The newest first-parent commit in the monorepo that changed `<path>/.splice`. Derived, never stored. |
| **default branch** | A repository's main branch (`HEAD` on the remote). The monorepo's default branch corresponds to upstream's. |
| **base** | The branch the current branch was cut from. Defaults to the default branch; `--base` overrides it for stacked branches. |

## The `.splice` file

Each splice has a `<path>/.splice` file, committed with the folder:

```
[splice]
	url = git@github.com:x/a.git
	commit = 3f1c…        # the synced commit U
	default-branch = master   # only if upstream's differs from the monorepo's
```

- **Git's config format, read and written by Git:**
  `git config --file <path>/.splice splice.commit`. There's no parser of
  our own, and the file is never sourced, since that would run whatever
  someone commits into it.
- **It contains no monorepo SHAs.** The boundary is derived from history
  instead, so rebases and squash merges can't break it.
- **It moves with the folder** (`git mv`), and stores no path. The folder
  that contains it is the splice. Discovery:
  `git ls-files -- '*/.splice'`.
- **It's never pushed upstream:** the push rebuild leaves the entry out of
  every exported tree. A pull adds it back.
- **Two branches that both pulled** conflict in this file. To start with,
  you resolve that by hand by keeping the newer synced commit. A merge
  driver can follow if a scenario shows it's needed.

## No Git remotes

Upstream commits are fetched by URL into private refs:

```
git fetch <url> '+refs/heads/*:refs/splices/<path>/*'
```

- No Git remote exists, so nothing can push the monorepo there by mistake.
  That fixes #50 by design, not by intercepting it.
- `url.<base>.insteadOf` and `pushInsteadOf` still apply, since they work
  on URLs.
- A push goes to the URL, so `push` updates `refs/splices/<path>/<branch>`
  itself afterwards.
- **Nested splices are refused.** `refs/splices/vendor/a/b/main` would be
  ambiguous between splice `vendor/a` (branch `b/main`) and splice
  `vendor/a/b`. The outer splice's push would also publish the inner one.

## Commands

The command is singular, like `git subtree` and `git submodule`. Which
splices a command acts on depends on what it does:

| Kind | Commands | Without a path |
|---|---|---|
| Splices in or out: changes the monorepo or an upstream repository | `clone`, `init`, `merge`, `pull`, `push` | Refuses. Takes one or more paths, or `--all`. |
| Looks or prepares: changes neither | `status`, `diff`, `log`, `fetch`, `prune` | Every splice; paths narrow it down. |

Splicing in writes a commit into the monorepo, and splicing out publishes
commits upstream. Both should name their target, as `git push <remote>`
does. An overview such as `status` is only useful if it's complete.

### Starting a splice

| Situation | Command |
|---|---|
| Upstream exists, the folder doesn't | `git splice clone <url> [<path>]` |
| The folder exists, upstream is new or empty | `git splice init <path> <url>` |
| Both exist with the same content | `git splice clone <url> <path>`: only writes `.splice`, since nothing can be lost |
| Both exist and differ | `git splice clone --merge <url> <path>` |

- `clone` refuses a folder that exists and differs from upstream, like
  `git clone` refuses a non-empty directory. The message names `--merge`
  and what it does.
- `--merge` runs the same mechanism as `merge`, with an empty folder as the
  base. Every file that differs becomes an add/add conflict, and nothing is
  lost. Merging on a branch that deleted and re-cloned the folder
  **isn't** a substitute: its merge base still has the folder, so Git takes
  upstream's side wholesale and drops local-only files.
- `init` refuses an upstream that already has commits, and points to
  `clone --merge`. Otherwise it writes `.splice` without a synced commit,
  and the first push creates the upstream branch from the folder's history.
- The name `add` is avoided on purpose: it suggests `git add`.

### `pull` = `fetch` + `merge`

`merge` turns already fetched upstream changes into **one ordinary
commit** in the monorepo, and never touches the network:

1. Build two throwaway commits whose trees have the monorepo's layout:
   - **base:** HEAD's tree, with `<path>/` replaced by U's tree and its
     `.splice`.
   - **T:** HEAD's tree, with `<path>/` replaced by the new upstream commit
     U2 and a `.splice` that records U2. T's parent is base.
2. Run `git cherry-pick T`. That's a three-way merge with base as the merge
   base, HEAD as ours and T as theirs. Only `<path>/` differs between base
   and T, so only the splice can conflict. Local edits are kept, and the
   `.splice` update comes along in the same commit. Git's ort merge does the
   work, including rename detection.

The `git subtree` way needs two commits per pull because it needs a merge
base in history. Re-rooting the trees supplies that merge base explicitly
instead.

- **On a conflict:** resolve it, then run `git commit`. It finishes the
  cherry-pick and keeps the prepared message. Abort with
  `git cherry-pick --abort`. `git status` will say "cherry-picking" although
  you ran `merge`, so `merge` should mention both commands when it stops.
- **base and T are never referenced** and get garbage-collected. Upstream
  commits stay in `refs/splices/` and never become ancestors of HEAD.
- **A dry run** for `status` and `diff` uses
  `git merge-tree --write-tree --merge-base=<base> HEAD <T>`, which doesn't
  touch the worktree. It needs Git 2.40.

### `push`: the rebuild

A push sends the splice's history since the last sync, rebuilt as upstream
commits. The rebuild is a function of B, U and HEAD:

1. B is `git log --first-parent -1 --format=%H -- <path>/.splice`, and U is
   the synced commit recorded at B.
2. If `B:<path>` (without `.splice`) differs from U's tree, start with one
   synthetic commit on top of U with that tree. That happens when a squash
   merge mixed local edits into the commit that changed `.splice`.
3. For each commit in
   `git rev-list --reverse --first-parent B..HEAD -- <path>`, run
   `git commit-tree` with `<commit>:<path>` minus `.splice`. Copy author
   **and committer, including their dates**, as `git subtree split`'s
   `copy_commit` does. Read the message with `--pretty=format:%B`, not
   `--format=` (which adds a trailing newline).

**Deterministic:** the same history always rebuilds into the same commits.
That's what makes `status` possible without storing anything (see below),
and commits pushed earlier are rebuilt identically, so the next push
fast-forwards.

**First parent only:** a merge in the monorepo, e.g. `git merge main` on a
feature branch, becomes **one ordinary commit** upstream. It keeps the
original message, even though it has a single parent. Upstream doesn't
know about the monorepo's side branches, so a faithful merge shape would
add nothing. Leaving it out avoids the parent-mapping problems that `split`
spent years fixing.

**Costs** O(commits since the last sync), not O(all history), which fixes
#30. The first push after `init` rebuilds the folder's whole history once.

**Never writes to the monorepo.** Recording each push as a sync point was
tried in
[#28](https://github.com/roschaefer/git-subtrees/pull/28) and dropped:
merging a branch that pushed brings its push record along, pointing at the
wrong remote branch.

### `status`

A push needs no state, so `status` works it out each time:

1. R is the rebuild of HEAD, and T is `refs/splices/<path>/<branch>`. If no
   first-parent commit after B touched the path and `B:<path>` equals U,
   then R = U without rebuilding anything.
2. Compare R and T:

| Comparison | State |
|---|---|
| No `refs/splices/<path>/*` at all | never fetched |
| No ref for this branch | no branch on remote: changed against base? `push` creates it |
| R = T, or equal trees | up to date |
| T is an ancestor of R | push |
| R is an ancestor of T | pull |
| A common ancestor, neither contains the other | diverged |
| No common ancestor | unrelated history |

These are the states `git-subtrees` reports today, including the rule
that a missing remote branch is created only if the splice changed against
the base branch.

### `diff` and `log`

- **`diff`** shows the file changes a push would send: `git diff T R`, or
  for a missing remote branch, from the merge base with the base branch.
- **`log`**
  ([git-subtrees#51](https://github.com/roschaefer/git-subtrees/issues/51))
  shows commits, in both directions:

  ```
  git log --left-right --cherry-mark R...refs/splices/<path>/<branch>
  ```

  `<` marks what a push sends, `>` what a pull brings, and `=` a commit
  upstream already applied by cherry-pick or rebase. The default format
  shows author and committer: a push publishes both, and they may be a
  private identity.

### Branches

- Each splice syncs with the upstream branch named like the monorepo's
  current branch. Switching branches switches every splice. This holds for
  every command, whichever splices it acts on.
- The monorepo's default branch maps to upstream's default branch. `clone`
  and `init` look it up with `git ls-remote --symref <url> HEAD`, and write
  `default-branch` into `.splice` only if it differs. Recording it keeps it
  stable if upstream renames its default branch later.
- "Default branch" belongs to a repository and is stored in `.splice`.
  "Base" belongs to one command run and is given as `--base`. "Fallback"
  would describe only one of the uses.

## Testing

### Scenarios and acceptance tests

As in `git-subtrees`, each state is a scenario under `test/scenarios/`, with
a scrut-checked README. Two acceptance tests pin down the design:

- **No Git remote exists that can receive the monorepo.** After every
  command, `git remote` lists no splice.
- **A pull adds exactly one first-parent commit and no upstream ancestors.**

New scenarios, besides the existing states:

- a pull on a feature branch that gets squash-merged into `main`;
- the same with a rebase;
- merges where both branches pulled (a conflict in `.splice`);
- `clone` on a folder with identical content, and `clone --merge` on one
  that differs (add/add conflicts, nothing lost);
- merging a pushed `feature-2` into `feature-1` (the walkthrough's step 5)
  and `pushed-then-changed`.

### `git subtree split` as the test oracle

`split` has years of fixes behind it, and the rebuild copies metadata the
same way. So on histories where both apply, the rebuild must produce
**identical SHAs**. That reuses `split`'s maturity in the tests without
running it in production.

To keep the comparison fair:

- Oracle fixtures are built with `git subtree add --squash`, and the
  rebuild gets B and U as arguments.
- `.splice` stays out of oracle fixtures. `split` would include it in every
  tree, so its removal is tested separately.

**Approved divergences.** These scenarios assert that the rebuild differs
from `split`, and their READMEs show both outputs side by side:

1. **A merge in the monorepo becomes one commit.** Everything before the
   merge is identical; from the merge on, the SHAs differ:

   ```
   --- git subtree split (oracle):              --- first-parent rebuild:
   * 2098669 feature: after merge               * 4f27765 feature: after merge
   *   7584029 Merge branch 'main' into feature * 0f2628d Merge branch 'main' into feature
   |\                                           * 875a02b feature: g
   | * e6d52a2 main: h                          * e6d54f9 f2
   * | 875a02b feature: g                       * 9e9685e f1
   |/                                           * 153c9a7 up 1
   * e6d54f9 f2
   ```

2. **A squash-merged pull.** `split` rebuilds a duplicate of the upstream
   commit; the rebuild starts at the boundary and doesn't. Here the oracle
   is wrong.
3. **A rebased pull:** the same, for a rebase.

## Requirements and non-goals

- **Requirements:** Bash 4.4 and Git 2.40. No compilation: wherever Git
  can do a job, the tool calls Git.
- **Not supported:** nested splices; a faithful copy of the monorepo's
  merge shapes upstream; migrating `git-subtrees` monorepos. To switch,
  push everything, then `clone` each folder again.

## Repository

`git splice` lives in `roschaefer/git-splice`. It started as a branch of
`roschaefer/git-subtrees`, so it carries over that tool's history, tests,
scenarios and CI. Both are remotes of one clone, so fixes can move between
them while `git-subtrees` is still in use.
