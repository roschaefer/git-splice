# Design

A handful of principles explain why `git-splice` behaves the way it
does, and they decide what it does next: a
[change](../08-contributing/README.md#pull-requests) that needs a
different tradeoff revisits the principle it departs from.

## Principles

- **Keep each repository's history relevant to its users.** A pull adds
  one commit to the monorepo, not the library's history. A push sends
  the splice's changes since the last sync, not the monorepo's other
  work, and not what the folder held before it became a splice: that
  may never have been meant for this upstream.
- **Store as little state as possible.** A `.splice` file records one
  upstream commit, the last sync. Everything else, like which monorepo
  commits the next push sends, is worked out from history each time, so
  no second record can fall out of step. `git-subrepo` shows the cost:
  every push commits a record to the monorepo, and
  [a squash merge loses it](../05-comparisons/02-third-party/01-git-subrepo.md#problem-3-after-a-squash-merge-the-last-sync-is-lost)
  ([state rationale](02-state.md#derive-state-instead-of-storing-redundant-records)).
- **Nesting should not change a splice's meaning.** `vendor/a/b/` in the
  monorepo syncs as `b/` does in a clone of `a`'s repository, so a
  library needs no other workflow because it sits inside another one.
  That needs [state that travels with the folder](02-state.md#sync-state-belongs-in-versioned-files),
  inner history that a squash above it hid
  ([scenario](../09-scenarios/05-nested-splices/01-nested-splices/pushed-and-made-above.md)),
  and outer rebuilds that record each inner splice at the commit its own
  upstream gets in the same push, so a clone of the outer upstream
  rebuilds the inner splice as the monorepo does
  ([scenario](../09-scenarios/05-nested-splices/01-nested-splices/rebuilt-in-layers.md)).
- **Rebuild deterministically.** Rebuilding the same history gives the
  same commit IDs, so the next push fast-forwards from the last one
  without a monorepo commit recording it. Rebuilt commits keep their
  original author, committer and dates and aren't signed: the current
  time, user or a signature would change the IDs
  ([sync model](../03-concepts/02-sync-model.md#r-is-computed-not-stored)).
- **Keep repeated syncs scalable.** A rebuild starts at the last sync
  point, so its cost grows with the commits since then, not with all of
  history, as [`git subtree split --squash`](../05-comparisons/01-git/02-git-subtree.md#problem-2-with---squash-split-walks-everything)
  does. Moving the sync point costs a monorepo commit, so a
  [bump](../04-advanced-workflows/03-bump.md) does it when you choose,
  not on every push.
- **Preserving monorepo commit topology is a non-goal.** A rebuild
  follows first parents, so a branch merged in the monorepo reaches
  upstream as one commit
  ([scenario](../09-scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/02-merge-in-monorepo/README.md)).
  The branch's own commits stay in the monorepo. Mapping every merge, as
  [`git subtree`](../05-comparisons/01-git/02-git-subtree.md) and
  [Josh](../05-comparisons/02-third-party/02-josh.md) do, adds much
  complexity for little benefit so far.
- **Inspection must predict publication.** `status`, `diff` and `log`
  look at the same rebuilt commits that `push` sends, so what they show
  is what the upstream gets
  ([sync model](../03-concepts/02-sync-model.md#how-r-and-t-determine-the-status)).
- **Ask “what would Git do?”** Where Git solved a problem well,
  `git-splice` does the closest equivalent, like
  [branch-tracking settings](../09-scenarios/03-branches-and-teamwork/07-tracked-branch/README.md)
  and [reflogs](../09-scenarios/06-rewritten-history/04-patch-branch-rebased/README.md).
  Where a Git design causes problems, like the global tag namespace or
  submodules, it doesn't
  ([upstream choices](03-upstreams.md),
  [submodule comparison](../05-comparisons/01-git/01-git-submodule.md)).
- **Git's words keep Git's meaning.** A word Git uses means the same
  here: `pull` fetches and merges, as `git pull` does. Where the meaning
  differs, `git-splice` takes a word Git hasn't, like
  [splice](01-name.md#noun-and-verb).
- **Take advantage of Git's full power.**
  [Rebasing a pushed feature branch](../04-advanced-workflows/README.md)
  or [editing rebuilt commits before a push](../09-scenarios/06-rewritten-history/01-edited-before-push/README.md)
  is done with Git. `git-splice` combines its commands with Git's rather
  than becoming another history editor.
- **Use the user's Git so repository operations remain observable.**
  `git-splice` runs the installed `git`, so it uses your version, and
  `GIT_TRACE` lists every Git command it runs
  ([scenario](../09-scenarios/01-everyday-sync/05-git-trace/README.md)).
  A library such as gitoxide would hide that, and be another
  implementation of Git to maintain.
- **Make information easy to discover and side effects deliberate.**
  Without a path, `status`, `diff`, `log` and `fetch` cover every
  splice, so a change in a splice you forgot about still shows up.
  `pull`, `merge` and `push` need a path or `--all`, so they never
  change or publish a splice you didn't name.
- **Design for pull requests across repositories.** A monorepo feature
  branch is work to submit upstream, so `push` sends it to the upstream
  branch of the same name, ready for a PR to that upstream. Until
  there's something to push, the splice is compared with upstream's
  default branch
  ([branch rationale](03-upstreams.md#matching-branch-names-keep-a-feature-together)).
- **Refuse rather than guess.** A guess can discard changes or publish
  to the wrong place. When two branches pulled the same splice, merging
  them conflicts on the synced commit, and `git-splice` doesn't pick
  one: `pull` refuses to start until you
  [resolve it](../09-scenarios/03-branches-and-teamwork/04-concurrent-pulls/README.md),
  and a `.splice` committed with conflict markers stops every command.
- **Weigh every fix against its complexity.** A fix can bring more
  failure modes than it removes, and every later change pays for it.
  A rare case can be documented or tracked as an
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
