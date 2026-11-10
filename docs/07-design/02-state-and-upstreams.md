# State and upstreams

The shared sync state must survive history rewrites and use by other VCS
tools. Fetched upstream state and personal branch choices can stay local,
following Git's model. The [architecture](README.md#architecture) shows
where each belongs.

## Derive state instead of storing redundant records

Every stored value creates work to keep it consistent. Storing both a
result and the information needed to derive it lets those records drift
apart after a partial update or history rewrite. Avoiding that redundant
bookkeeping was a motivation for departing from
[`git-subrepo`](../05-comparisons/02-third-party/01-git-subrepo.md).

B, R and the sync status are therefore derived from committed history and
fetched refs. A push does not need a monorepo commit to record its result:
a later deterministic rebuild recovers it. A proposed state field should
explain why existing history and configuration cannot supply the value,
rather than introduce another record that commands must keep in sync.

## Sync state belongs in versioned files

Extra commit metadata ties the relationship to tools that understand and
preserve it. Keeping `.splice` in the worktree's versioned contents lets
other VCS tools carry that state as an ordinary file, even when they use
their own extra metadata. A rebase or squash likewise need not understand
a special sync record to preserve it. This avoids depending on
special handling of commit metadata, as
[Sapling does](../05-comparisons/03-vcs/01-sapling.md), or sync records in
[commit messages](../05-comparisons/01-git/02-git-subtree.md#problem-3-the-sync-points-are-in-commit-messages),
as `git subtree` does.

Committing the file also makes the relationship available in a fresh clone
and lets ordinary Git switch and merge it between branches. Sync commands read its committed version so an
unfinished edit cannot silently change the relationship they use.

### Keep state inside the folder to avoid a redundant path

The minimum-state principle applies to paths too: `.splice` already
identifies its folder by living inside it. Recording that path separately,
as `.gitmodules` does for submodules, creates another value to keep in sync.
A move can leave that record stale. Keeping `.splice` inside the splice
lets ordinary folder moves carry the relationship without a second update.

### Recorded references must survive history rewrites

A stored monorepo commit ID would become stale when history is
rewritten, so the file records an upstream commit instead. The nesting
principle also rules out storing a path or commit specific to the outermost
monorepo: that reference would lose its meaning in a standalone clone of
the enclosing upstream.

### Reuse an available, established config format

Every `git-splice` user already needs Git installed, so its config reader
and writer are available without another dependency. Its established
format provides sections and values without a parser of our own to
maintain. Sourcing the file as a script would instead let committed
configuration execute commands.

### Avoid interfering with build and packaging tools

Spliced files remain part of the monorepo's normal build and packaging
inputs. `.splice` was chosen to clash with no known configuration file,
so tools discovering files do not mistake the relationship for their own
configuration.

### Identity must distinguish replacements and remain repeatable

A random ID would make otherwise identical initialisations differ. Path
alone cannot distinguish a moved splice from a replacement at its old
location. Deriving the ID from the path, `HEAD`, upstream URL and imported
commit makes the same operation repeatable while distinguishing different
upstreams introduced at the same path. Keeping that ID through moves lets
the rebuild recover the right history
([identity](../03-concepts/03-splice-identity.md)).

### Conflicting sync points require a deliberate decision

Choosing either `.splice` mechanically can claim that a merged folder
contains an upstream state it does not actually contain. There is no
automatic merge driver today; adding one would need to establish that
relationship, not merely resolve the configuration text
([concurrent pulls](../09-scenarios/03-branches-and-teamwork/04-concurrent-pulls/README.md)).
An upstream with a root `.splice` is likewise refused because importing
it would overwrite the file defining the outer relationship.

## Fetched state belongs to each clone

A folder can move, and the same path can name different upstreams on
different branches. Keying refs by path would lose the former's fetched
state or confuse the latter's. URL keys also let several splices share
one fetch while retaining independent committed sync points. The registry
belongs in local Git config, shared with worktrees just as the refs are;
committing it would impose one clone's naming choices on everyone.

### Private refs avoid an accidental push target

Registering an upstream as a remote makes it available to plain Git push,
branch tracking and IDE sync actions, any of which can send monorepo
history. Fetching by URL into private refs keeps upstream objects usable
by ordinary Git commands without adding that accidental push target.
[Safety and limits](05-safety-and-limits.md) compares the rejected guards
and explains the remaining risk of an explicit push by URL.

### Exact URLs identify upstreams without guessing equivalence

Similar spellings can identify different repositories: `host:lib` is
relative to the remote home folder, while `ssh://host/lib` is not.
Merging their fetched state would be incorrect. Identity is therefore
decided before local `insteadOf` expansion; URL rewrites remain transport
preferences rather than changes to the committed relationship.

### Local ref names must stay portable and unambiguous

URLs can contain characters and lengths unsuitable for ref names.
Lower-case, bounded keys avoid case collisions and path-length growth,
while recognisable names keep refs usable in ordinary Git commands.
[Key naming](../06-command-reference/11-key.md#keys) gives the exact rules.

Worktrees share this registry. Checking and writing independently would
let simultaneous commands choose the same free key for different URLs.
Conflicting hand-edited mappings must also be refused rather than letting
one upstream overwrite another's refs. Read-only commands do not allocate
keys, so inspecting a checkout does not silently create local state.

### Reflogs preserve evidence of branch movement

A fetched branch can be rewritten, leaving its previous tip unreachable
from the new one. Like Git's remote-tracking refs, splice refs keep
reflogs, so a merge can look for a rewritten branch's fork point. Reusing
Git's record of ref updates avoids inventing a separate history of fetches.

### Separate tag namespaces prevent unrelated releases from colliding

Unrelated repositories commonly reuse names such as `v1.0`. Importing
their tags into one `refs/tags/` namespace would make them collide.
Ordinary fetches therefore skip tags; a tag needed for a pin is fetched
under its upstream's private refs. Following Git's successful patterns
does not mean repeating its shared tag namespace across repositories.

### Fetched refs must reflect known upstream changes

Pruning removes deleted branches without a separate maintenance command.
Updating the fetched ref after publication lets inspection see the push
immediately. If that update fails, the command must report it even though
publication has succeeded: otherwise a successful-looking operation would
leave a misleading local view.

## Branch selection follows the project

### Matching branch names keep a feature together

The intended workflow is to develop a feature on a monorepo branch and
submit its changes through PRs in the affected upstream repositories.
Assuming the same feature branch name on both sides connects that work
without requiring a separate branch choice for every splice.

A PR needs a target to compare against before its source branch has been
published. The upstream's default branch supplies that target, with a
mapping where default branch names differ. Deriving the prospective
changes from that target lets inspection show what a PR would contain.
Only upstreams with commits to submit need a feature branch; eagerly
creating one in every upstream would leave branches with no corresponding
PR work ([scenario](../09-scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/README.md)).

### Recorded defaults prevent silent retargeting

Rediscovering the default branch on every operation would let an upstream
rename change the meaning of an existing checkout. Recording differing
defaults makes that choice stable and reviewable. It belongs to each
upstream because a fork and its origin can use different branch names.

### Tracking choices stay local, following Git

Git keeps the choice of which upstream branch a local branch tracks in
local config. Splice tracking follows that established model rather than
introducing a different scope for the same kind of choice. Defaults and
pins describe the relationship the team checks out together; tracking
overrides describe one developer's workflow, so committing them would
retarget everyone else. A command-line choice takes precedence so
a stored preference cannot prevent a deliberate one-off operation.
An immutable pin cannot serve as a publication branch. The selection
rules are defined with
[tracking](../03-concepts/01-upstreams.md#tracking-another-upstream-branch-locally)
and [pins](../09-scenarios/04-upstreams/06-default-pin/README.md).

### Inherited defaults must retain their meaning outside the monorepo

The [nesting principle](README.md#principles) makes the enclosing
repository the source of inherited settings. Falling back to the outermost
monorepo would make the same nested
`.splice` mean something different when its enclosing upstream is cloned
independently. When an enclosing pin or differing defaults leave no
unambiguous branch to inherit, requiring an explicit choice is safer than
silently selecting a different target
([nesting](../03-concepts/04-nesting.md#settings-come-from-the-splice-above)).
