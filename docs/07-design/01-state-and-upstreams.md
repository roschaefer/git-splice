# State and upstreams

The storage boundary should let ordinary Git operations carry a splice's
meaning with its files, while each clone fetches and inspects upstreams
independently. The [architecture](README.md#architecture) shows that boundary;
[Concepts](../03-concepts/README.md) defines the stored state.

## The `.splice` file

- **Keep the relationship with the files so ordinary Git can manage it.**

  A local-only registry would make a fresh clone incomplete and require
  separate machinery to switch or merge splice relationships between
  branches. Committing `.splice` lets Git carry those choices with the
  folder. Reading the committed version keeps sync decisions tied to
  recorded history rather than an unfinished edit to the relationship.

- **Avoid references that a move or rebase would invalidate.**

  A stored folder path would need updating whenever the folder moves;
  a stored monorepo commit ID would become stale when that history is
  rewritten. The file therefore travels with the folder and records an
  upstream commit instead. The nesting principle also rules out storing
  a path or commit specific to the outermost monorepo: that reference would
  lose its meaning in a standalone clone of the enclosing upstream.

- **Reuse Git's config parser without executing repository content.**

  A separate parser would add another format implementation to maintain.
  Sourcing the file as a script would let committed configuration execute
  commands. Git's config format provides sections and values through Git's
  own reader and writer, without treating the file as code.

- **Use a distinct filename to avoid interfering with the project's tools.**

  Spliced files remain part of the monorepo's normal build and packaging
  inputs. `.splice` was chosen to clash with no known configuration file,
  so tools discovering files do not mistake the relationship for their own
  configuration.

- **Derive identity so repeatable operations do not invent new history.**

  A random ID would make otherwise identical initialisations differ. Path
  alone cannot distinguish a moved splice from a replacement at its old
  location. Deriving the ID from the path, `HEAD`, upstream URL and imported
  commit makes the same operation repeatable while distinguishing different
  upstreams introduced at the same path. Keeping that ID through moves lets
  the rebuild recover the right history
  ([identity](../03-concepts/03-splice-identity.md)).

- **Record upstream defaults so a remote rename cannot silently retarget a sync.**

  Rediscovering the default branch on every operation would let an upstream
  rename change the meaning of an existing checkout. Recording differing
  defaults makes that choice stable and reviewable. It belongs to each
  upstream because a fork and its origin can use different branch names.

- **Leave conflicting sync points for a deliberate merge decision.**

  Choosing either `.splice` mechanically can claim that a merged folder
  contains an upstream state it does not actually contain. There is no
  automatic merge driver today; adding one would need to establish that
  relationship, not merely resolve the configuration text
  ([concurrent pulls](../09-scenarios/03-branches-and-teamwork/04-concurrent-pulls/README.md)).
  An upstream with a root `.splice` is likewise refused because importing
  it would overwrite the file defining the outer relationship.

## Refs instead of remotes

- **Make accidental publication harder without requiring per-clone guards.**

  Registering an upstream as a remote makes it available to plain Git push,
  branch tracking and IDE sync actions, any of which can send monorepo
  history. Fetching by URL into private refs keeps upstream objects usable
  by ordinary Git commands without adding that accidental push target.
  [Safety and limits](04-safety-and-limits.md) compares the rejected guards
  and explains the remaining risk of an explicit push by URL.

- **Key fetched state by upstream URL so moves and branch switches cannot mix it up.**

  A folder can move, and the same path can name different upstreams on
  different branches. Keying refs by path would lose the former's fetched
  state or confuse the latter's. URL keys also let several splices share
  one fetch while retaining independent committed sync points. The registry
  belongs in local Git config, shared with worktrees just as the refs are;
  committing it would impose one clone's naming choices on everyone.

### Keys belong to URLs

- **Use exact URLs rather than guessing repository equivalence.**

  Similar spellings can identify different repositories: `host:lib` is
  relative to the remote home folder, while `ssh://host/lib` is not.
  Merging their fetched state would be incorrect. Identity is therefore
  decided before local `insteadOf` expansion; URL rewrites remain transport
  preferences rather than changes to the committed relationship.

- **Use short, safe keys rather than embedding URLs in ref paths.**

  URLs can contain characters and lengths unsuitable for ref names.
  Lower-case, bounded keys avoid case collisions and path-length growth,
  while recognisable names keep refs usable in ordinary Git commands.
  [Key naming](../06-command-reference/11-key.md#keys) gives the exact rules.

- **Allocate keys under a lock so concurrent fetches cannot claim the same refs.**

  Worktrees share this registry. Checking and writing independently would
  let simultaneous commands choose the same free key for different URLs.
  Conflicting hand-edited mappings must also be refused rather than letting
  one upstream overwrite another's refs. Read-only commands do not allocate
  keys, so inspecting a checkout does not silently create local state.

- **Keep fetched refs consistent with the upstream changes the tool knows about.**

  Pruning removes deleted branches without a separate maintenance command.
  Updating the fetched ref after publication lets inspection see the push
  immediately. If that update fails, the command must report it even though
  publication has succeeded: otherwise a successful-looking operation would
  leave a misleading local view.

## Branches

- **Follow one feature across repositories without managing separate checkouts.**

  Matching feature branch names let a monorepo branch carry coordinated
  changes across upstreams. Default branches need a mapping because their
  names can differ. Comparing a missing feature branch with the upstream's
  default target makes the prospective PR visible before publication;
  creating branches only when there is something to publish avoids empty
  branches in unrelated upstreams
  ([push design](03-splicing-out.md#new-upstream-branches)).

- **Separate shared dependency choices from personal branch choices.**

  Defaults and pins describe the relationship the team checks out together.
  Tracking overrides describe one developer's workflow; committing them
  would retarget everyone else. A command-line choice takes precedence so
  a stored preference cannot prevent a deliberate one-off operation.
  An immutable pin cannot serve as a publication branch. The selection
  rules are defined with
  [tracking](../03-concepts/01-upstreams.md#tracking-another-upstream-branch-locally)
  and [pins](../09-scenarios/04-upstreams/06-default-pin/README.md).

- **Inherit nested defaults from their enclosing repository to preserve meaning across clones.**

  The [nesting principle](README.md#principles) makes the enclosing
  repository the source of inherited settings. Falling back to the outermost
  monorepo would make the same nested
  `.splice` mean something different when its enclosing upstream is cloned
  independently. When an enclosing pin or differing defaults leave no
  unambiguous branch to inherit, requiring an explicit choice is safer than
  silently selecting a different target
  ([nesting](../03-concepts/04-nesting.md#settings-come-from-the-splice-above)).
