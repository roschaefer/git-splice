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
- **Refuse rather than guess.** With unrelated histories, or a path that
  can't be a ref name, the tool stops and says what to do.
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
can change it, and a push does not update the sync point
([example](../../test/scenarios/up-to-date/push-ahead/pushed-then-pulled/README.md)).

From that point, `git-splice` lets Git merge upstream changes and resolve
conflicts, or rebuild the folder's monorepo commits for a push. Changes cross
the boundary, but commits do not: both repositories keep their own histories.

## How it compares

[Comparisons](../../test/comparisons/README.md) runs `git submodule` and
`git subtree` side by side with `git splice`, and
[third-party tools](../../test/comparisons/third-party/README.md) compares
git-subrepo, splitsh-lite, Josh and Copybara.

## Vocabulary

| Term | Meaning |
|---|---|
| **splice** | A folder of the monorepo that has its own upstream repository: "`vendor/a` is spliced in from `github.com/x/a`", "the `vendor/a` splice". Strictly, the noun means the joint, not the inserted piece. |
| **path** | Where the splice lives in the monorepo, e.g. `vendor/a`. (`git subtree` calls it `--prefix`.) |
| **upstream** | The splice's own repository, named and given by URL in `.splice`, like a Git remote. |
| **state file** | `<path>/.splice`. Its presence in `HEAD` makes the folder a splice. |
| **synced commit** (U) | The upstream commit `.splice` records: the one last spliced in. |
| **boundary** (B) | The newest first-parent commit in the monorepo that changed `<path>/.splice`. Derived, never stored. |
| **rebuild** (R) | The splice's changes in the monorepo, rebuilt as upstream commits. What `push` sends, and *ours* when compared with T, in the upstream's history; in the monorepo's history, *ours* is HEAD. |
| **upstream branch** (T, for *theirs*) | `refs/splices/<key>/<branch>`: the upstream branch as the monorepo last saw it, under the upstream's key. |
| **key** | An upstream's short name in one repository, e.g. `lib`, mapped to its URL in the repository's config. Names its refs. |
| **splice in** | Bring upstream content into the monorepo: `clone`, `merge`, `pull`. |
| **splice out** | Publish the monorepo's changes upstream: `push`. |
| **sync state** | How R and T relate: `up to date`, `push`, `pull`, `diverged` and so on. |
| **default branch** | A repository's main branch (`HEAD` on the remote). The monorepo's default branch corresponds to upstream's. |
| **nested splice** | A splice below another one's folder. Commands that change things go top-down (`merge`, `pull`: the splice above first) or bottom-up (`push`: the splice below first). |
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
 │ refs/splices/<key>/*     (T) │                  │
 └──────────────────────────────┘                  │
        │ merge: cherry-pick of re-rooted trees    │
        │ push: rebuild of B..HEAD on top of U ────┘
```

The state lives in two places, and both are plain Git data:

- **Committed:** `<path>/.splice`, with the upstream's URL and the synced
  commit U.
- **Local, rebuilt by `fetch`:** `refs/splices/<key>/<branch>`, a copy of
  every upstream branch, under a key the repository's config maps the
  upstream's URL to.

Everything else, B, R and the sync state, is derived from those two and
the monorepo's history each time a command runs.

### Code map

`git-splice` checks the Bash and Git versions, sources `lib/*.sh`, and
dispatches `git splice <command>` to `cmd_<command>`. The libraries are
layered, each using only the ones above it:

| File | Responsibility |
|---|---|
| `lib/common.sh` | Discovery (`discover_splices`), argument parsing and path selection, reading and writing `.splice` (`splice_config`, `state_blob`), upstream keys (`upstream_key`, `create_upstream_key`), branch mapping, base branch resolution. |
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
	commit = 3f1c…              # the synced commit U
	default-branch = master     # only if upstream's differs from the monorepo's
[upstream "origin"]
	url = git@github.com:x/a.git
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
  `HEAD`, at any depth, not the index: a staged `.splice` isn't a splice
  yet.
- **A splice's own push never sends it.** The rebuild drops the entry at
  the splice's root from every tree it exports; a pull adds it back. The
  `.splice` of a nested splice is content of the splice above it, whose
  push sends it (see below). Build or package globs in the monorepo do see it,
  which is fine: the name clashes with no known configuration file.
- **Without `default-branch`**, the upstream's default branch has the
  name of the default branch of what the splice lives in: the splice
  above it, or the monorepo. So a nested `.splice` means the same in the
  monorepo as in the upstream above, where the repository stands in for
  the splice above
  ([example](../../test/scenarios/nested-default-branch/README.md)).
- **Its `default-branch`** is looked up once, by `clone` and `init`, and
  recorded only when it differs from that default branch. That keeps it stable if upstream later
  renames its default branch, and visible to anyone wondering why `main`
  syncs with `master`.
- **Its upstream is named**, like a Git remote, so a library can later
  sync with more than one, e.g. a company fork and the original. Exactly
  one `[upstream "<name>"]` is supported for now. `clone` and `init` name
  it `origin`. `commit` stays one per splice: a sync point is a commit,
  whichever upstream it came from. A `.splice` from before names, with
  `splice.url`, makes every command stop and print the commands that
  convert it.
- **Every command checks it can read it.** A `.splice` that `git config`
  can't parse, e.g. one committed with conflict markers, stops every
  command with Git's message, instead of being half read.
- **Two branches that both pulled** conflict in this file. You resolve it
  by keeping the newer synced commit. A merge driver can follow if that
  turns out to be common.

## Refs instead of remotes

Upstream branches are fetched by URL into private refs:

```
git fetch --prune <url> '+refs/heads/*:refs/splices/<key>/*'
```

The key is the upstream's short name in this repository. The first
command that fetches an upstream records it in the repository's config,
which all its worktrees share, as they share the refs:

```
[splice "lib"]
	url = https://github.com/x/lib.git
```

It comes from the end of the URL, without `.git`, in lower case: `lib`
for `https://github.com/x/lib.git`. If that's taken, by another URL or by
refs left under it, more of the URL goes in front, `x-lib`, then
`github.com-x-lib`, and only then a number. Lower case only, so no two
keys' refs share files on a case-insensitive file system, and short, so
they fit any file system's name limit. Commands record keys one at a
time, under a lock, and refuse a config edited by hand into keys that
aren't valid, or into two URLs for a key or two keys for a URL, naming
the `git config` command that fixes it. A key has no `/`, so branch names, which may, start right
after it. `git splice key <path>` prints a splice's key, and
`git splice key <path> <new-key>` renames it, refs included. Commands
that only read, like `status`, never record a key: an upstream without
one hasn't been fetched.

The URL is the one written in `.splice`, before `insteadOf`. Spellings
that look alike can name different repositories, e.g. `/srv/lib` and
`/srv/lib.git`, or `host:lib` (relative to the home folder) and
`ssh://host/lib`, so only equal URLs share a key. Keys are local, like the
refs: two clones may give one upstream different keys.

Keyed by URL, not by path, the refs describe the upstream rather than the
folder:

- `git mv` keeps the URL, so a moved splice still finds its refs.
- Splices at the same path with different upstreams, e.g. on two
  branches, don't overwrite each other's refs, and `init` on a path that
  had another upstream doesn't see that one's refs.
- Splices with equal URLs share refs, which is fine, since refs only
  describe the upstream. `fetch` fetches each upstream once.

- No Git remote exists, so nothing can push the monorepo there by mistake.
  [Why that matters](accidental-monorepo-push.md).
- `url.<base>.insteadOf` and `pushInsteadOf` still apply, since they work
  on URLs.
- `push` goes to the URL, and then updates `refs/splices/<key>/<branch>`
  itself. If it can't, the push counts as failed.
- `--prune` drops branches deleted upstream, so no `prune` command is
  needed.
- Every Git command can read an upstream as `splices/<key>/<branch>`,
  as of the last fetch. No separate clone is needed:

  ```
  git log --oneline splices/a/main
  git show splices/a/main:README.md
  git worktree add --detach ../a-upstream splices/a/main
  ```

  `git log --all` and `gitk --all` show those histories too; add
  `--exclude='refs/splices/*'` before `--all` to leave them out.

Two rules follow from the layout:

- **A splice nested in another is a splice on both sides.** Each push
  sends its folder without its own `.splice`, so the push of the splice
  above sends the `.splice` of the one below along with its files. In the
  upstream of the splice above, the folder below is then a splice too, which `git splice` can
  pull and push there. The `.splice` holds nothing specific to the
  monorepo, and fetched refs are keyed by URL, so both repositories find
  the same synced commit under the same refs. An upstream with a `.splice`
  at its root is refused: it would replace the splice's own.
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
  first push creates the upstream branch with one commit, the init
  commit. The folder's history before it isn't published: it was written
  for the monorepo, and may hold what was removed before anyone decided
  to publish the folder
  ([example](../../test/scenarios/init-new-upstream/removed-before-init/README.md)).
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
   - **theirs:** HEAD's tree, with `<path>/` replaced by the upstream branch's
     tree and a `.splice` that records its commit. Its parent is base.
2. Run `git cherry-pick theirs`. That's a three-way merge of HEAD (ours)
   and theirs, with base as the merge base. Only `<path>/` differs between
   base and theirs, so only the splice can conflict. Local edits are kept, and the
   `.splice` update comes along in the same commit. Git's ort merge does
   the work, including rename detection.

The merge base is `git merge-base R T`: the newest upstream commit both
sides contain. Usually that's U. After a push it's the pushed commit, which
spares the merge from replaying changes upstream already has.

- **On a conflict:** resolve it, then run `git commit`, which finishes the
  cherry-pick and keeps the prepared message. Abort with
  `git cherry-pick --abort`. `git status` says "cherry-picking" although
  you ran `merge`, so `merge` names both commands when it stops.
- **base and theirs are never referenced** and get garbage-collected. Upstream
  commits stay in `refs/splices/` and never become ancestors of HEAD.
- **Nested splices:** a pull of a splice brings in the `.splice` files
  below it as its upstream has them, and becomes the boundary of those
  splices. If its upstream moved the synced commit of a splice below, the
  rebuild joins that splice's unpushed commits with the new one, as after
  a pull of a divergence. `pull` fetches the splices below too, so their
  new synced commit is there.
  - **Top-down:** `merge` and `pull` take a splice before the ones below
    it. Pulling the one below first, to a commit newer than the one the
    upstream above records, would make the pull above conflict. A pull
    that removed a `.splice` below ends that splice, and its pull is
    skipped. A failed fetch stops the pull of the splices above and below
    it, and a failed merge the merges below it.
  - **Bottom-up:** `push` takes a splice before the ones above it, whose
    push publishes its `.splice`, and a failed push stops them. Otherwise
    the upstream above would record content the upstream below doesn't
    have.

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
   A rebuild of B's first parent that shares no history with U isn't
   joined, as `git merge` refuses unrelated histories: the folder was
   another splice there, e.g. after two folders swapped paths, and B goes
   on top of U.
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
splice made by `init`: `.splice` doesn't count as a change, so on a
feature branch where the folder's content didn't change, its first push
publishes nothing. Push it from the default branch instead
([#3](https://github.com/roschaefer/git-splice/issues/3)).

### `status`: the sync state

`classify_splice` works the state out each time, from R and T:

| Condition | State |
|---|---|
| No `refs/splices/<key>/*`, and U is recorded but isn't available locally (a fresh clone of the monorepo) | never fetched |
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
  git log --left-right --cherry-mark R...refs/splices/<key>/<branch>
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

- **A nested splice pulled on both sides:** if the monorepo and the
  upstream of the splice above each pull the splice below, the next pull
  of the splice above conflicts in the folder below, since each side
  brought in a different upstream commit. If the monorepo has no unpushed
  changes there, keep the upstream's side:
  `git checkout --theirs -- <above>/<below>`, then `git add` and
  `git commit`. Pushing the splice above right after pulling the one below
  avoids the conflict.
- **Paths that aren't valid in ref names**, e.g. with spaces, are refused.
- **Moving a splice with unpushed changes:** the `git mv` commit changes
  `.splice`, so it becomes the boundary, and the unpushed commits before it
  reach upstream folded into the move commit. Push before moving
  ([#4](https://github.com/roschaefer/git-splice/issues/4)).
- **Upstream URLs that differ only in letter case**, e.g.
  `ssh://host/Org/lib` and `ssh://host/org/lib`, share their fetched refs
  on case-insensitive file systems, like macOS's default one: fetching one
  overwrites the other's. And a URL component that is too long once
  escaped, e.g. many spaces, fails with "File name too long". Until
  [#51](https://github.com/roschaefer/git-splice/issues/51), avoid
  upstreams whose URLs differ only in case, and long path components.
- **A splice made by `init`** has no synced commit until its first pull, so
  until then every rebuild walks the folder's history since `init`.
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
| Scenarios | `test/scenarios/**/setup.bash` | Nothing on its own: one function that builds a monorepo and an upstream in one state, nested under the scenario it continues from. Shared by everything below. |
| Unit and command tests | `test/*.bats` | Functions and commands, called directly after `load_lib`, against a scenario. |
| Oracle tests | `test/rebuild.bats` | The rebuild against `git subtree split`. |
| Scenario READMEs | `test/scenarios/**/*.md` | What the tool prints in that state, checked by scrut. |
| Walkthroughs | `test/walkthrough/*.md` | Every command in order, on a sandbox, checked by scrut. |
| Benchmark | `bench/`, `test/bench.bats` | `status` timings on a synthetic monorepo, reported on PRs out of draft. |

### Writing a bats test

```bash
setup() {
  load 'helpers/fixtures'
  load_lib                  # source lib/*.sh, to call functions directly
  hermetic_git_config       # ignore the developer's git config
  load 'scenarios/up-to-date/push-ahead/setup'
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
