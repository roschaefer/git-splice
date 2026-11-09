# Research: Git behaviour, issue context, and LFS

## Issue #445 as fetched on 2026-11-08

Title: `pull --recursive --exec <cmd>: stop at the splice whose update breaks the build`

https://github.com/roschaefer/git-splice/issues/445

At fetch time the issue was open with no comments. Its important points:

- Recursive pull updates many splices and folds their pulls into one commit.
  A broken build afterward does not identify the offending update.
- Recursive work is on `pile/recursion`, draft PR #439; #432 is the carved PR
  for recursive pull itself. New work belongs on the pile or a branch off it.
- Existing loop: top-down merges, reload configs, discover nested splices.
  Conflicts stop it; re-running uses synced state to skip completed merges.
- Fold start persists in `SPLICE_PULL_START`; a non-pull commit between pulls
  prevents folding them.
- Suggested semantic checkpoints: after fetch/discover, after each merge,
  before fold. `--exec` for build checks initially needs after-merge only.
- Context: checkpoint name, path, old/new synced commits, etc.
- Existing reference-transaction hook observes ref changes but lacks splice/pass
  context; refusing a prepared ref transaction interrupts Git mid-command rather
  than giving a clean semantic pause.
- Open questions: baseline build before first merge; folding versus preserving
  intermediate commits; recursive rebase can wait for #437.

The user's later discussion broadens the design to caller-owned continuation
payloads and scripts at multiple operation types; do not limit implementation
to the issue's initial after-merge build flag without considering that steering.

## Direct experiment: Git 2.56.0 rebase exec

In a temporary repository with base -> one -> two, ran:

```fish
git rebase --force-rebase --exec 'exit 7' BASE
```

Observed:

- Rebase applied commit `one`, then ran `exit 7`.
- The rebase process returned 1, not 7.
- HEAD remained at `one`; there was no rollback of that commit.
- `.git/rebase-merge/git-rebase-todo` contained only:

```text
pick <two> # two
exec exit 7
```

- `git rebase --continue` applied `two` and stopped at its failing exec.
  It did NOT retry the exec after `one`.

Repeated with `--reschedule-failed-exec`:

- Same first stop at `one`.
- Remaining todo began with `exec exit 7`, followed by pick two and its exec.
- `--continue` retried that exec and stopped again without applying `two`.

The experiment used isolated Git config and a temporary local identity; no
user/global config was changed. Repository was left with the rebase aborted.
The temporary path was `/tmp/splice-exec-study-9dmoynm5` but may not survive
future sessions; the findings above are the durable result.

## Git sources

- https://git-scm.com/docs/git-rebase
  - Exec runs shell commands from working-tree root, normally via /bin/sh,
    independent of the user's interactive fish shell.
  - A failing command interrupts rebase with exit status 1.
  - Rescheduling failed exec is optional and defaults to false.
- https://raw.githubusercontent.com/git/git/master/sequencer.c
  - Defines `rebase-merge/git-rebase-todo`, backup, `done`, head/options and
    related state files.
  - Instructions are removed from the front of todo and appended to done as
    processed. Rebase resumes a recorded sequence, not just inferred HEAD state.
  - Cherry-pick/revert also have `sequencer/todo`, `opts`, `head` paths.
- https://git-scm.com/docs/githooks
  - `post-checkout` runs after checkout/switch updates (also clone/worktree add
    under documented conditions).
  - `post-merge` runs after successful git merge, not conflicted merges, and
    cannot affect the merge outcome.
  - These hooks are too late to prefetch content needed by the checkout itself,
    and do not cover every plumbing/cherry-pick path git-splice uses.

No assumption should be made that current Git master source details are stable
APIs. Use their design as reference, not internal paths as git-splice storage.

## LFS sources and findings

Official primary sources inspected:

- https://raw.githubusercontent.com/git-lfs/git-lfs/main/docs/man/git-lfs-install.adoc
  - Configures clean/smudge filters and installs pre-push hook.
  - --skip-smudge disables automatic content downloading on checkout.
  - --skip-repo skips local hook installation.
- https://raw.githubusercontent.com/git-lfs/git-lfs/main/docs/man/git-lfs-fetch.adoc
  - `git lfs fetch <remote> <ref>...` downloads objects for specified refs.
  - Does not update the working copy.
  - Include/exclude paths affect which objects are downloaded; default remote
    selection uses tracking/origin. Correct explicit upstream context matters.
- https://raw.githubusercontent.com/git-lfs/git-lfs/main/docs/man/git-lfs-config.adoc
  - `.lfsconfig` is read at repository root, with index/HEAD fallbacks.
  - `lfs.url`, per-remote LFS URL settings, push URLs, autodetection and other
    settings affect endpoint selection.
  - A nested splice's `.lfsconfig` is not automatically root configuration of
    the monorepo. Passing an upstream URL does not by itself solve custom endpoint
    configuration; investigate before claiming full support.
- https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-pre-push.adoc
  was opened, but no new upload experiment was performed. Existing executable
  repository scenarios are the evidence for splice push already working.

## Existing repository LFS scenarios

`docs/09-scenarios/04-upstreams/08-lfs-upstream/README.md`:
normal splice clone fails while smudging `vendor/a/model.bin`, because content
is in the upstream LFS store rather than the monorepo's default remote.

`clone-by-hand.md` demonstrates the workaround:

1. Clone splice with `GIT_LFS_SKIP_SMUDGE=1`, leaving committed pointers.
2. A normal monorepo push fails if the LFS objects are missing locally.
3. Fetch the content from upstream for its fetched splice ref.
4. `git lfs checkout vendor/a` materializes the content.
5. Normal monorepo push uploads it to the monorepo's LFS server.
6. A colleague can then clone the monorepo normally, without git-splice.

Equivalent fish commands (variables must be set by the scenario):

```fish
env GIT_LFS_SKIP_SMUDGE=1 git splice clone "file://$UPSTREAM" vendor/a
set splice_key (git splice key vendor/a)
git lfs fetch "file://$UPSTREAM" "refs/splices/$splice_key/heads/main"
git lfs checkout vendor/a
```

`01-cloned-by-hand/README.md`: adding a new LFS-tracked file in the splice and
running `git splice push` already uploads it through LFS's ordinary pre-push
hook; a new upstream clone gets its content.

`01-cloned-by-hand/01-retrained-upstream/README.md`: a later upstream model
change again needs correct upstream LFS fetching for pull.

Fresh LFS execution remains unverified in this session because git-lfs was not
installed on the plain shell PATH. The existing scenario outputs were read,
not rerun. Keep that distinction in progress reports.
