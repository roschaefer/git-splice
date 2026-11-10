# Upstreams

An upstream connection must travel with the splice without exposing an
accidental way to publish the whole monorepo. Its configuration therefore
belongs in `.splice`, separate from ordinary Git remotes. Fetched data and
personal tracking choices stay local, following Git's model.

## Upstream connections must not become ordinary Git remotes

A private monorepo containing folders with public upstreams is a core use
case. Publishing the monorepo's history to one of those upstreams would
disclose private source code and data.

An early predecessor registered splice upstreams as ordinary Git remotes.
That made an ordinary `git push`, branch-tracking setup or IDE sync action
capable of sending the entire private history to a public repository.
New branches and forced pushes bypass the non-fast-forward rejection that
might otherwise stop it.

Deleting the public branch does not reliably retract the disclosure.
GitHub can retain commits through cached views and pull-request references,
and copies in other people's clones or forks remain beyond the author's
control ([GitHub's removal guidance](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)).
The design must prevent this accidental publication path rather than rely
on every user choosing correctly or being able to undo a mistake.

### Why not guard a remote?

| Alternative | Why it was not chosen |
| --- | --- |
| A `pre-push` hook inspecting commits | Each clone must install it; `--no-verify` bypasses it; it competes with other hook managers. A path-based check can reject a legitimate library containing the same path. |
| A deliberately invalid push URL | Blocks normal pushes, but the wrapper must push to the fetch URL and update refs itself. Errors and tools that inspect push URLs become confusing. |
| A custom remote helper | Can reject ordinary pushes clearly, but every Git client needs the helper installed. Supporting multiple transports and tools that interpret URLs adds complexity. |
| Server-side restrictions | Require control over the upstream server or hosting rules; they cannot protect pushes to arbitrary upstreams. |

Git documents [push hooks](https://git-scm.com/docs/githooks#_pre_push),
[separate fetch/push URLs](https://git-scm.com/docs/git-remote) and
[remote helpers](https://git-scm.com/docs/gitremote-helpers). The choice here
is to avoid adding a subfolder remote in the first place.

### Keep the connection in configuration Git does not treat as a remote

The upstream connection belongs in the versioned `.splice` file, which
`git-splice` interprets and ordinary Git remote selection does not. This
keeps the relationship available in every clone without making it a push
target for branch tracking, IDE sync actions or ordinary Git commands.
Fetching and pushing by URL into private refs still lets Git handle the
repository operations, without a hook or helper installed in each clone.

Typing an upstream URL into a plain Git push remains possible. The design
removes accidental remote selection; it cannot prevent a user explicitly
asking Git to send monorepo history to a URL.

For the different tradeoffs of a centrally operated export pipeline, see
[Copybara and ShipIt](../05-comparisons/02-third-party/04-export-tools.md).

## Fetched state belongs to each clone

A folder can move, and the same path can name different upstreams on
different branches. Keying refs by path would lose the former's fetched
state or confuse the latter's. URL keys also let several splices share
one fetch while retaining independent committed sync points. The registry
belongs in local Git config, shared with worktrees just as the refs are;
committing it would impose one clone's naming choices on everyone.

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
