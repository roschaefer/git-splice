# State

Shared sync state must survive history rewrites and use by other VCS tools.
The [architecture](README.md#architecture) separates that versioned state
from [local upstream data](03-upstreams.md).

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
