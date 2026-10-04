# git-splice: design

`git splice` keeps folders of a monorepo in sync with their own upstream
repositories, in both directions. Switching branches in the monorepo
switches the branch every folder syncs with.

## Design goals

### Keep configuration with the folder

Cloning the monorepo should be enough to use every splice. Its URL and sync
state live in a committed `.splice` file, not in `.git/config`. Fetching and
pushing by URL also prevents a plain `git push` from sending the whole
monorepo to a splice's upstream.

### Make sync state explicit

`status` should not scan the monorepo's entire history or depend on a merge
commit surviving a rebase or squash merge. Each splice records the upstream
commit it last matched, so commands only inspect history since that point.

### Keep the histories separate

Working in a monorepo should not import upstream's history. A pull creates one
ordinary monorepo commit. A push rebuilds the commits that changed the folder
as upstream commits. Changes cross the boundary; commits do not.

## Principles

- **Let Git do the work.** Bash and Git, nothing to compile. Wherever Git
  can do a job, the tool calls Git: `git config` parses the state file,
  `cherry-pick` merges, `commit-tree` rebuilds, `log --left-right` compares.
  The tool's own code connects these, and stays small.
- **Changes cross the boundary, commits don't.** The monorepo and each
  upstream keep separate histories. Upstream commits never become
  ancestors of the monorepo's commits, and the monorepo's merges and side
  branches never reach upstream.
- **The folder carries its own state.** A splice is a folder with a
  committed `.splice` file. Nothing about it lives in `.git/config`, so a
  clone of the monorepo has every splice, and `git mv` moves one.
- **Store as little as possible, derive the rest.** `.splice` holds the
  URL and the upstream commit the folder last matched, never a monorepo
  SHA. Where the last sync happened in the monorepo, and whether a push is
  needed, are worked out from history each time. Nothing a rebase or squash
  merge does can make them stale.
- **Deterministic rebuilds.** The same history always rebuilds into the
  same upstream commits, byte for byte. That makes status computable
  without storing anything about earlier pushes, and lets a second push
  fast-forward over the first.
- **Branches follow the monorepo.** On `feature-x`, every splice syncs with
  its upstream's `feature-x`. No branch is fixed per folder.
- **Name the target when writing, show everything when looking.** Commands
  that change the monorepo or an upstream need a path or `--all`.
  Commands that only look cover every splice.
- **Refuse rather than guess.** With unrelated histories, nested splices,
  or a path that can't be a ref name, the tool stops and says what to do.
- **Weigh every fix against its complexity.** An easy, safe fix goes in.
  A rare case gets documented, or an issue labelled
  [`edge case`](https://github.com/roschaefer/git-splice/issues?q=label%3A%22edge+case%22). An extreme one is ignored.

## The sync point

A splice is an ordinary folder in the monorepo with a committed `.splice`
file. Like a subtree, its files live directly in the monorepo, where they can
be changed and tested with everything else. Like a submodule, the monorepo
records an upstream repository and one of its commits.

The commit has a different meaning than a submodule's gitlink. A submodule
commit says which revision should be checked out. A splice commit is a sync
point: the upstream revision the folder matched when changes were last spliced
in. It does not determine the folder's current content; later monorepo commits
can change it, and a push does not update the sync point.

From that point, `git-splice` lets Git merge upstream changes and resolve
conflicts, or rebuild the folder's monorepo commits for a push. Changes cross
the boundary, but commits do not: both repositories keep their own histories.

## How it compares

| Tool | What is similar | Key difference |
| --- | --- | --- |
| `git submodule` | The monorepo commits an upstream URL and commit. | A submodule commit selects the revision in a separate worktree. A splice commit only marks an earlier sync point; the folder is ordinary monorepo content and may have changed since. |
| `git subtree` | The files live in the monorepo and are developed there. | A subtree has no state file. Pulling imports upstream history or a squash commit and merge; a splice records its sync point and pulls as one ordinary monorepo commit, which a squash merge can't lose ([example](../../test/scenarios/squash-merged-pull/README.md)). A monorepo merge reaches upstream as one commit, not as the monorepo's side branches ([example](../../test/scenarios/merge-in-monorepo/README.md)). |
| [git-subrepo](https://github.com/ingydotnet/git-subrepo) | It has a committed state file, fetches by URL and pulls as one commit. | It stores a monorepo commit that rebases and squash merges can invalidate, and fixes each folder to one branch. |
| [splitsh-lite](https://github.com/splitsh/lite) | It publishes folders as repositories. | It creates read-only mirrors; changes only flow out. |
| [Josh](https://github.com/josh-project/josh) | It exposes part of a monorepo as a repository. | The monorepo remains authoritative, and contributors work through filtered views of it. |
| [Copybara](https://github.com/google/copybara) | It moves changes between repositories. | One repository is the source of truth; syncing back needs a separate reverse workflow ([example](../../test/scenarios/copybara-contributor-workflow/README.md)). |

## Vocabulary

| Term | Meaning |
|---|---|
| **splice** | A folder of the monorepo that has its own upstream repository: "`vendor/a` is spliced in from `github.com/x/a`", "the `vendor/a` splice". Strictly, the noun means the joint, not the inserted piece. |
| **path** | Where the splice lives in the monorepo, e.g. `vendor/a`. (`git subtree` calls it `--prefix`.) |
| **upstream** | The splice's own repository, given by URL. |
| **state file** | `<path>/.splice`. Its presence in `HEAD` makes the folder a splice. |
| **synced commit** (U) | The upstream commit whose content the splice last matched, recorded in `.splice`. |
| **boundary** (B) | The newest first-parent commit in the monorepo that changed `<path>/.splice`. Derived, never stored. |
| **rebuild** (R) | The upstream history that the monorepo's commits since B turn into. What `push` sends. |
| **upstream branch** (T) | `refs/splices/<path>/<branch>`: the upstream branch as last fetched. |
| **splice in** | Bring upstream content into the monorepo: `clone`, `merge`, `pull`. |
| **splice out** | Publish the monorepo's changes upstream: `push`. |
| **sync state** | How R and T relate: `up to date`, `push`, `pull`, `diverged` and so on. |
| **default branch** | A repository's main branch (`HEAD` on the remote). The monorepo's default branch corresponds to upstream's. |
| **base** | The branch the current branch was cut from. Defaults to the default branch; `--base` overrides it for stacked branches. |

"Default branch" belongs to a repository and is stored in `.splice` when
needed. "Base" belongs to one command run. Neither is called "fallback",
which would describe only one of their uses.

## Architecture

```
          monorepo                                upstream (by URL)
 ┌──────────────────────────────┐
 │ HEAD                         │  fetch   ┌───────────────────────────┐
 │  └ vendor/a/                 │ <─────── │ refs/heads/*              │
 │      ├ .splice  (url, U)     │          └───────────────────────────┘
 │      └ …                     │                  ^
 │                              │                  │ push R
 │ refs/splices/vendor/a/*  (T) │                  │
 └──────────────────────────────┘                  │
        │ merge: cherry-pick of re-rooted trees    │
        │ push: rebuild of B..HEAD on top of U ────┘
```

The state lives in two places, and both are plain Git data:

- **Committed:** `<path>/.splice`, with the URL and the synced commit U.
- **Local, rebuilt by `fetch`:** `refs/splices/<path>/<branch>`, a copy of
  every upstream branch.

Everything else, B, R and the sync state, is derived from those two and
the monorepo's history each time a command runs.

### Code map

`git-splice` checks the Bash and Git versions, sources `lib/*.sh`, and
dispatches `git splice <command>` to `cmd_<command>`. The libraries are
layered, each using only the ones above it:

| File | Responsibility |
|---|---|
| `lib/common.sh` | Discovery (`discover_splices`), argument parsing and path selection, reading and writing `.splice` (`splice_config`, `state_blob`), branch mapping, base branch resolution. |
| `lib/rebuild.sh` | The push rebuild: `splice_boundary`, `rebuild_splice` and its commit loop `rebuild_walk`. |
| `lib/state.sh` | `classify_splice`, the sync state every command acts on, and `splice_in`, the re-rooted cherry-pick behind `merge` and `clone --merge`. |
| `lib/pager.sh` | Paging for `diff` and `log`. |
| `lib/<command>.sh` | One command each: usage text, `cmd_<command>`, and its per-splice step. |

Each command follows the same shape: `select_paths` picks the splices,
then a per-splice function (`merge_one`, `push_one`, …) calls
`classify_splice` and acts on its state.

## The `.splice` file

```
[splice]
	url = git@github.com:x/a.git
	commit = 3f1c…              # the synced commit U
	default-branch = master     # only if upstream's differs from the monorepo's
```

- **Git's config format, read and written by Git:**
  `git config --file <path>/.splice splice.commit`. There's no parser of
  our own, and the file is never sourced, since that would run whatever
  someone commits into it. It looks like TOML, but isn't.
- **Only `clone`, `init`, `merge` and `pull` write it.** `push` never
  changes the monorepo.
- **It contains no monorepo SHAs.** The boundary is derived from history
  instead, so rebases and squash merges can't break it.
- **It stores no path.** The folder that contains it is the splice, and it
  moves along with `git mv`. Discovery reads every `*/.splice` committed in
  `HEAD`, not the index: a staged `.splice` isn't a splice yet.
- **It's never pushed upstream.** The rebuild drops the entry at the
  splice's root from every tree it exports; a pull adds it back. Build or
  package globs in the monorepo do see it, which is fine: the name clashes
  with no known configuration file.
- **Its `default-branch`** is looked up once, by `clone` and `init`, and
  recorded only when it differs. That keeps it stable if upstream later
  renames its default branch, and visible to anyone wondering why `main`
  syncs with `master`.
- **Two branches that both pulled** conflict in this file. You resolve it
  by keeping the newer synced commit. A merge driver can follow if that
  turns out to be common.

## Refs instead of remotes

Upstream branches are fetched by URL into private refs:

```
git fetch --prune <url> '+refs/heads/*:refs/splices/<path>/*'
```

- No Git remote exists, so nothing can push the monorepo there by mistake.
  [Why that matters](accidental-monorepo-push.md).
- `url.<base>.insteadOf` and `pushInsteadOf` still apply, since they work
  on URLs.
- `push` goes to the URL, and then updates `refs/splices/<path>/<branch>`
  itself. If it can't, the push counts as failed.
- `--prune` drops branches deleted upstream, so no `prune` command is
  needed.
- Every Git command can read an upstream as `splices/<path>/<branch>`,
  as of the last fetch. No separate clone is needed:

  ```
  git log --oneline splices/vendor/a/main
  git show splices/vendor/a/main:README.md
  git worktree add --detach ../a-upstream splices/vendor/a/main
  ```

  `git log --all` and `gitk --all` show those histories too; add
  `--exclude='refs/splices/*'` before `--all` to leave them out.

Two rules follow from the ref layout:

- **No nested splices.** `refs/splices/vendor/a/b/main` would be ambiguous
  between splice `vendor/a` (branch `b/main`) and splice `vendor/a/b`, and
  the outer splice's push would publish the inner one. Discovery, `clone`
  and `init` refuse them, and `clone` and `merge` refuse an upstream that
  contains a `.splice` of its own.
- **A splice's path must work in a ref name** (`git check-ref-format`),
  which applies to the whole path: no spaces, no component ending in
  `.lock`, and so on.

## How the commands work

Which splices a command acts on depends on what it does:

| Kind | Commands | Without a path |
|---|---|---|
| Starts a splice | `clone`, `init` | Take one URL and one path, no `--all`. `clone` defaults the path to the repository's name, as `git clone` does. |
| Splices in or out: changes the monorepo or an upstream | `merge`, `pull`, `push` | Refuses. Takes one or more paths, or `--all`. |
| Looks or prepares: changes neither | `status`, `diff`, `log`, `fetch` | Every splice; paths narrow it down. |

Splicing in writes a commit into the monorepo, and splicing out publishes
commits upstream. Both should name their target, as `git push <remote>`
does. An overview such as `status` is only useful if it's complete.

### Starting a splice: `clone` and `init`

| Situation | Command |
|---|---|
| Upstream exists, the folder doesn't | `git splice clone <url> [<path>]` |
| The folder exists, upstream is new or empty | `git splice init <path> <url>` |
| Both exist with the same content | `git splice clone <url> <path>`: only writes `.splice`, since nothing can be lost |
| Both exist and differ | `git splice clone --merge <url> <path>` |

- `clone` refuses a folder that exists and differs from upstream, like
  `git clone` refuses a non-empty directory. The message names `--merge`.
- `--merge` runs the same mechanism as `merge` (below), with an empty
  folder as the merge base. Every file that differs becomes an add/add
  conflict, and nothing is lost. Deleting the folder on a branch,
  re-cloning it there and merging `main` back **isn't** a substitute: the
  merge base still has the folder, so Git takes upstream's side wholesale
  and drops local-only files.
- To replace the folder with upstream's version instead, `git rm` it in one
  commit, then `clone` into the empty spot.
- `init` refuses an upstream that already has commits, and points to
  `clone --merge`. It writes `.splice` without a synced commit, and the
  first push creates the upstream branch from the folder's whole history.
- The name `add` is avoided on purpose: it suggests `git add`.

### Splicing in: `merge`, and `pull` = `fetch` + `merge`

`merge` turns already fetched upstream changes into **one ordinary
commit** in the monorepo, and never touches the network. The problem it
solves: upstream's commits have the splice's content at their root, while
the monorepo has it at `<path>/`, and they share no history, so Git can't
merge them directly. `git subtree` solves that by putting upstream's
history into the monorepo's. `merge` instead supplies the merge base
explicitly:

1. Build two throwaway commits whose trees have the monorepo's layout
   (`reroot_tree`, using a temporary index):
   - **base:** HEAD's tree, with `<path>/` replaced by the merge base's
     tree and HEAD's `.splice`.
   - **T:** HEAD's tree, with `<path>/` replaced by the upstream branch's
     tree and a `.splice` that records its commit. T's parent is base.
2. Run `git cherry-pick T`. That's a three-way merge with base as the merge
   base, HEAD as ours and T as theirs. Only `<path>/` differs between base
   and T, so only the splice can conflict. Local edits are kept, and the
   `.splice` update comes along in the same commit. Git's ort merge does
   the work, including rename detection.

The merge base is `git merge-base R T`: the newest upstream commit both
sides contain. Usually that's U. After a push it's the pushed commit, which
spares the merge from replaying changes upstream already has.

- **On a conflict:** resolve it, then run `git commit`, which finishes the
  cherry-pick and keeps the prepared message. Abort with
  `git cherry-pick --abort`. `git status` says "cherry-picking" although
  you ran `merge`, so `merge` names both commands when it stops.
- **base and T are never referenced** and get garbage-collected. Upstream
  commits stay in `refs/splices/` and never become ancestors of HEAD.

### Splicing out: `push` and the rebuild

A push sends the splice's history since the last sync, rebuilt as upstream
commits. `rebuild_splice` is a function of HEAD alone:

1. **Find the boundary.** B is
   `git log --first-parent -1 -- <path>/.splice`. Every `clone`, `init`
   and pull writes such a commit, and no rebase or squash merge can remove
   all of them. U is the synced commit recorded at B.
2. **Start at U.** If B's folder (without `.splice`) equals U's tree, the
   rebuild continues from U. If it differs, a pull merged a divergence, or
   a squash merge mixed local edits into the commit that changed
   `.splice`. Then B is rebuilt as a commit with B's folder, whose parents
   are the rebuild of B's first parent (recursively) and U. Local commits
   that were never pushed keep their identity, and upstream gets them
   joined with its own by a merge, as a plain `git pull` would have made.
   The recursion stops at the first boundary whose folder equals its
   synced commit, so it only costs something after pulls of divergences.
3. **Copy each commit.** For each commit in
   `git rev-list --reverse --first-parent B..HEAD -- <path>` whose folder
   changed, `git commit-tree` with the folder's tree minus `.splice`.
   Author and committer are copied, **including their dates**, as
   `git subtree split`'s `copy_commit` does. The message is read with
   `--pretty=format:%B`, not `--format=`, which would add a newline.
   Commits are never signed: a signature would differ from run to run.

**Deterministic:** commits pushed earlier are rebuilt identically, so the
next push fast-forwards, and `status` can compare R with T without
remembering anything.

**First parent only:** a merge in the monorepo, e.g. `git merge main` on a
feature branch, becomes **one ordinary commit** upstream, with the merge's
message. Upstream doesn't know the monorepo's side branches, so a faithful
merge shape would add nothing, and leaving it out avoids the
parent-mapping problems `split` spent years fixing.

**Costs** O(commits since the last boundary whose folder matched its synced
commit), not O(all history). The commit loop
reads all commit metadata with one `git log` and all folder trees with one
`git cat-file --batch-check`, so it spawns about one process per commit.

**Never writes to the monorepo.** Recording a push as a sync point would be
incorrect: merging a branch that pushed would bring that record onto another
upstream branch.

**A new upstream branch** is created only if the splice changed on this
branch, measured against the base. So starting a feature branch doesn't
create empty branches on every upstream. The same rule applies to a
splice made by `init`, so its first push has to come from the default
branch: on a feature branch where the folder didn't change, it publishes
nothing ([#3](https://github.com/roschaefer/git-splice/issues/3)).

### `status`: the sync state

`classify_splice` works the state out each time, from R and T:

| Condition | State |
|---|---|
| No `refs/splices/<path>/*`, and U is recorded but isn't available locally (a fresh clone of the monorepo) | never fetched |
| No ref for this branch | upstream has no such branch |
| The splice's content equals T's tree, or R = T | up to date |
| T is an ancestor of R | push |
| R is an ancestor of T | pull |
| A common ancestor, neither contains the other | diverged |
| No common ancestor, or U isn't available locally | unrelated history |

The content check comes first: when the trees are equal, nothing needs
rebuilding.

### `diff` and `log`

- **`diff`** shows the file changes a push would send: `git diff T R`, or,
  for a missing upstream branch, from the merge base with the base branch.
- **`log`** shows commits in both directions:

  ```
  git log --left-right --cherry-mark R...refs/splices/<path>/<branch>
  ```

  `<` is on the left (local) side only, so a push sends it; `>` is on the
  upstream side only, so a pull brings it; `=` is a commit upstream already
  applied by cherry-pick or rebase. Ours on the left, theirs on the right,
  as in Git's conflict markers. The format shows the author, because a
  push publishes it and it may be a private identity.

### Branches

- Each splice syncs with the upstream branch named like the monorepo's
  current branch, for every command. Switching branches switches every
  splice.
- The monorepo's default branch maps to upstream's default branch
  (`default-branch` in `.splice` if the names differ). Every other branch
  keeps its name on both sides.
- The monorepo's default branch is `origin/HEAD`, else
  `init.defaultBranch`. If neither works, commands that need it ask for
  `--base` instead of guessing.

## Limits

These are known and accepted, each to keep the design simple:

- **Nested splices**, including an upstream that contains a `.splice`, are
  refused (see above).
- **Paths that aren't valid in ref names**, e.g. with spaces, are refused.
- **Moving a splice with unpushed changes:** the `git mv` commit changes
  `.splice`, so it becomes the boundary, and the unpushed commits before it
  reach upstream folded into the move commit. Push before moving
  ([#4](https://github.com/roschaefer/git-splice/issues/4)). After a move,
  run `git splice fetch <new path>`: the fetched refs stay under the old
  path ([#21](https://github.com/roschaefer/git-splice/issues/21)).
- **A splice made by `init`** has no synced commit until its first pull, so
  until then every rebuild walks the folder's whole history.
- **Rare edge cases** each have an issue labelled
  [`edge case`](https://github.com/roschaefer/git-splice/issues?q=label%3A%22edge+case%22).

## Testing

Tests are executable documentation: a test's name states one behaviour,
and a scenario's README shows the tool's real output. Run them in
`nix develop`:

```
just test                 # bats tests
just docs-check           # scenario READMEs and walkthroughs, via scrut
just docs-check --write   # update them after an intended output change
just ci                   # lint, fmt-check, test, docs-check
```

CI also runs the whole suite on the oldest supported versions, Bash 4.4
and Git 2.40, and their newer counterparts.

### The layers

| Layer | Where | What it checks |
|---|---|---|
| Scenarios | `test/scenarios/<name>/setup.bash` | Nothing on its own: one function that builds a monorepo and an upstream in one state. Shared by everything below. |
| Unit and command tests | `test/*.bats` | Functions and commands, called directly after `load_lib`, against a scenario. |
| Oracle tests | `test/rebuild.bats` | The rebuild against `git subtree split`. |
| Scenario READMEs | `test/scenarios/<name>/README.md` | What the tool prints in that state, checked by scrut. |
| Walkthroughs | `test/walkthrough/*.md` | Every command in order, on a sandbox, checked by scrut. |
| Benchmark | `bench/`, `test/bench.bats` | `status` timings on a synthetic monorepo, reported on PRs out of draft. |

### Writing a bats test

```bash
setup() {
  load 'helpers/fixtures'
  load_lib                  # source lib/*.sh, to call functions directly
  hermetic_git_config       # ignore the developer's git config
  load 'scenarios/push-ahead/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "push: writes nothing to the monorepo and creates no Git remote" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  …
}
```

- **Name the behaviour, not the steps:** `<command or function>: <what it
  does>`, e.g. `"changes_vs_base: a change to .splice alone doesn't
  count"`. The list of test names should read as a specification.
- **Start from a scenario** if one fits, so the test and the README show
  the same state. Otherwise build the state inline from the helpers in
  `test/helpers/fixtures.bash`: `make_bare_repo`, `seed_bare_repo`,
  `init_monorepo`, `add_splice`, `commit_local`, `fetch_splice`.
- **Fixtures don't use the code under test.** `add_splice` splices a
  folder in with raw plumbing, not `cmd_clone`, so a bug in `clone`
  doesn't fail every other test. Use `splice <command>` (the real
  entrypoint) only where a state needs a command's own result, e.g. an
  earlier push.
- **Assert on Git's data, not only on output:** SHAs, trees, `rev-list`
  counts, whether a ref or a remote exists.
- **Make sure the test can fail.** A test that passes because both sides
  are empty, or because a step never ran, proves nothing. Check the
  precondition too, e.g. that the rebuild has three commits before
  comparing it.
- **A bug fix starts with a failing test** that reproduces it.

### Writing a scenario

A scenario is one state a splice can be in, or one situation a command
has to handle. [`test/scenarios/README.md`](../../test/scenarios/README.md)
has the steps. In short:

1. `<name>/setup.bash` defines `scenario_<name>` (`-` becomes `_`), which
   builds the state from the fixture helpers, given a monorepo path and an
   upstream path.
2. `<name>/README.md` describes the state, with a hidden scrut block that
   builds it, and one `scrut` block per command, with only its `$ ` line.
3. `just docs-check --write` fills in the real output. Read it: it's the
   documentation, so it has to say what the prose claims.
4. Add a bats test that asserts the state, e.g. in `test/status.bats`.

`readme-setup.sh` fixes commit dates and ignores the developer's git
config, so commit hashes are the same on every run. Run `docs-check` twice
after a change; output that differs between runs is a bug in the setup.

### `git subtree split` as the test oracle

`split` has years of fixes behind it, and the rebuild copies metadata the
same way. So on histories where both apply, the rebuild must produce
**identical SHAs**. That reuses `split`'s maturity in the tests without
running it in production.

To keep the comparison fair:

- Oracle fixtures are built with `git subtree add --squash`, which `split`
  understands, and the test passes B and U to `rebuild_walk` directly.
- `.splice` stays out of oracle fixtures. `split` would include it in every
  tree, so its removal is tested separately.

**Approved divergences.** Where the rebuild deliberately differs from
`split`, the test asserts exactly how, and its name says
`approved divergence`:

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
   is wrong. A rebased pull behaves the same way, and has a test of its
   own.

A new divergence needs a reason it's right, and a test like these.
