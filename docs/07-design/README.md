# Design

A handful of principles explain why `git-splice` behaves the way it
does, and they decide what it does next: a
[change](../08-contributing/README.md#pull-requests) that needs a
different tradeoff revisits the principle it departs from.

## Principles

- **Keep each repository's history relevant to its users.** The
  monorepo's users don't need the library's whole history, and the
  library's users don't need the monorepo's unrelated work. So changes
  cross the splice, and the histories stay apart: a pull adds one
  commit. What the folder held before it became a splice may never have
  been meant for this upstream, so a push follows the splice, not the
  path.
- **Store as little state as possible.** Two records of the same thing
  can disagree, and every update is a chance to leave them so. What
  history, configuration and file locations already tell is worked out
  from them instead of stored again: `.splice` records only the last
  sync. Redundant records in `git-subrepo`, which
  [a squash merge strands](../05-comparisons/02-third-party/01-git-subrepo.md#problem-3-after-a-squash-merge-the-last-sync-is-lost),
  motivated this
  ([state rationale](02-state.md#derive-state-instead-of-storing-redundant-records)).
- **Nesting should not change a splice's meaning.** A project shouldn't
  need another workflow for its dependencies because it sits inside
  another repository. So `vendor/a/b/` syncs as `b/` does in a clone of
  `a`'s repository. That needs
  [state that travels with the folder](02-state.md#sync-state-belongs-in-versioned-files),
  inner history recovered from under a squash
  ([scenario](../09-scenarios/05-nested-splices/01-nested-splices/pushed-and-made-above.md)),
  and outer rebuilds that record each inner splice as its own upstream
  gets it
  ([scenario](../09-scenarios/05-nested-splices/01-nested-splices/rebuilt-in-layers.md)).
- **Rebuild deterministically.** A push should need no monorepo commit
  to record it. If the same history always rebuilds to the same
  commits, the next push simply fast-forwards from the last one. So
  nothing that changes between runs goes in: rebuilt commits keep their
  original metadata and aren't signed
  ([sync model](../03-concepts/02-sync-model.md#r-is-computed-not-stored)).
- **Keep repeated syncs scalable.** A sync shouldn't get slower as
  history grows, as [`git subtree split --squash`](../05-comparisons/01-git/02-git-subtree.md#problem-2-with---squash-split-walks-everything)
  does. Moving the sync point forward keeps rebuilds short, but costs a
  monorepo commit, so a [bump](../04-advanced-workflows/03-bump.md)
  leaves that tradeoff to the user instead of making it on every push.
- **Preserving monorepo commit topology is a non-goal.** Following
  first parents is enough for the use cases so far, and the original
  history stays in the monorepo
  ([scenario](../09-scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/02-merge-in-monorepo/README.md)).
  [`git subtree`](../05-comparisons/01-git/02-git-subtree.md) and
  [Josh](../05-comparisons/02-third-party/02-josh.md) show that mapping
  history faithfully adds much complexity for little benefit. A use case
  that needs it can reopen the question.
- **Inspection must predict publication.** If `status` or `diff` read
  local changes differently from `push`, they could promise something a
  push doesn't send. So they compare the same rebuilt history that
  `push` publishes
  ([sync model](../03-concepts/02-sync-model.md#how-r-and-t-determine-the-status)).
- **Ask “what would Git do?”** Git has far more experience with version
  control problems. Where its solution works well, `git-splice` does the
  closest equivalent, like
  [branch-tracking settings](../09-scenarios/03-branches-and-teamwork/07-tracked-branch/README.md)
  and [reflogs](../09-scenarios/06-rewritten-history/04-patch-branch-rebased/README.md).
  Where a Git design causes problems, like the global tag namespace or
  submodules, that's a reason not to copy it
  ([upstream choices](03-upstreams.md),
  [submodule comparison](../05-comparisons/01-git/01-git-submodule.md)).
- **Git's words keep Git's meaning.** Users bring their expectations
  from Git, so a word Git uses names the same thing here. Where the
  meaning differs, `git-splice` takes a word Git hasn't, like
  [splice](01-name.md#noun-and-verb).
- **Take advantage of Git's full power.** Git already shapes history
  well, as in [rebasing](../04-advanced-workflows/README.md) or
  [editing rebuilt commits](../09-scenarios/06-rewritten-history/01-edited-before-push/README.md).
  Doing that again would solve a solved problem worse and narrow the
  user's choices. `git-splice` streamlines work across repositories
  and leaves history editing to Git.
- **Use the user's Git so repository operations remain observable.**
  Running the installed `git` uses the user's version and lets them
  see every command it runs on their machine
  ([scenario](../09-scenarios/01-everyday-sync/05-git-trace/README.md)).
  A library such as gitoxide would hide that, and be another
  implementation to maintain.
- **Make information easy to discover and side effects deliberate.**
  A wrong scope costs little when looking and much when writing. Having
  to name splices before looking at them can hide the very change you
  need to see; the same broad default on a write could change or
  publish unrelated work. So `status` and `diff` cover every splice,
  and `pull` and `push` need a path or `--all`.
- **Design for pull requests across repositories.** A monorepo feature
  branch is work to submit upstream, so matching branch names connect
  it to the upstream PRs. Before a feature branch exists upstream,
  its default branch is what the work is compared with, and the branch
  is made only when there are commits to submit
  ([branch rationale](03-upstreams.md#matching-branch-names-keep-a-feature-together)).
- **Refuse rather than guess.** A guess about ambiguous history, targets
  or inputs can discard changes or publish to the wrong place. A refusal
  that explains the ambiguity lets the user decide before anything
  changes, as with
  [two pulls of the same splice](../09-scenarios/03-branches-and-teamwork/04-concurrent-pulls/README.md).
- **Weigh every fix against its complexity.** A fix can add more failure
  modes than it removes, and every later change pays for its
  complexity. So weigh how often a case happens and how much fixing it
  helps; a rare case can be documented or tracked as an
  [edge case](https://github.com/roschaefer/git-splice/issues?q=label%3A%22edge+case%22)
  instead of complicating the ordinary workflow.

## Architecture

<div align="center">

![Committed folder contents and .splice are separate from local fetched refs and configuration. The rebuild and sync state are derived from history and fetched commits; fetch, pull and push connect them to the upstream repository.](architecture.drawio.svg)

</div>

## Read more

- [Why the name "splice"](01-name.md), including "splicing in" and
  "splicing out"
- Why [state](02-state.md) and [upstreams](03-upstreams.md) work the way
  they do
- [Going forward](07-going-forward/README.md): ideas and open questions,
  not released behaviour
