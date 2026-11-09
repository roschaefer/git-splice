# State and upstreams

Portable splice state belongs in the committed folder. Fetch state and
per-clone choices belong in local Git refs and configuration
([architecture](README.md#architecture)).

## The `.splice` file

Only the `.splice` committed in `HEAD` counts. It identifies the splice,
names its upstreams and records the upstream commit the folder last
matched. It stores no path or monorepo commit ID: moves carry the file,
and history rewrites do not invalidate its recorded upstream commit.
[Concepts](../03-concepts/README.md) shows the format. An upstream with a
root `.splice` is refused because it would replace the file describing
the outer relationship.

Git reads and writes its own config format; there is no separate parser,
and the file is never sourced as code. Its `id` is derived from the path,
`HEAD`, upstream URL and imported commit, so the same operation produces
the same ID. Different upstreams at the same path still get different IDs.
The ID lets the rebuild follow a move and distinguish a replacement splice
([identity](../03-concepts/03-splice-identity.md)).

`clone` and `init` record `default-branch` when it differs from the
containing repository's default. It belongs to each upstream: a fork and
its origin may use different names. Committing the choice keeps it stable
if the upstream later renames its default branch. A `default-pin` can
instead select a tag or complete commit ID.

Concurrent pulls can conflict in `.splice`. There is no automatic merge
driver: choosing a sync point can require deciding which upstream state
the merged folder actually contains
([concurrent pulls](../09-scenarios/03-branches-and-teamwork/04-concurrent-pulls/README.md)).

## Refs instead of remotes

The ordinary branch fetch is:

```text
git fetch --prune --no-tags <url> '+refs/heads/*:refs/splices/<key>/heads/*'
```

A configured tag pin is fetched explicitly as well. Git can read these
refs and check them out in worktrees, without registering the upstream as
a remote that a plain push could select
([why that matters](04-safety-and-limits.md)). Deleted upstream branches
are pruned; a successful `git splice push` updates the fetched branch ref
itself so status sees what was published. Failure to update that ref is
reported even if the upstream push already succeeded.

### Keys belong to URLs

The first fetch records a short key in the repository's local config,
shared by its worktrees:

```text
[splice "lib"]
	url = https://github.com/x/lib.git
```

Short, recognisable keys keep Git refs readable without embedding an
arbitrary URL in a ref name. Lower-case, ref-safe, bounded names avoid
filesystem case collisions and path-length growth. Allocation takes a lock
so simultaneous fetches cannot claim the same key; ambiguous hand-edited
mappings must be refused rather than mixing repositories' objects.
The [key reference](../06-command-reference/11-key.md) documents naming
and collision rules.

URL equality is exact, before `insteadOf` expansion: `host:lib` and
`ssh://host/lib` can mean different repositories. The generated key makes
that URL safe for refs; it is not the URL escaped into a path. This also
keeps URLs differing only in case from colliding on case-insensitive file
systems. Each clone may choose different keys.

This separation has useful consequences:

- Moving a splice keeps its refs; replacing its upstream at the same
  path does not reuse another upstream's refs.
- Splices naming the same URL share fetched refs, so the URL is fetched
  once, while their committed sync points remain independent.
- `insteadOf` and `pushInsteadOf` still apply to the fetch and push URLs.
- Read-only commands do not allocate keys; an unallocated upstream has
  not been fetched here.

[`git splice key`](../06-command-reference/11-key.md) prints or renames a
key, moving its refs and tracking settings with it.

## Branches

One monorepo feature branch can carry changes across several repositories.
Matching upstream branch names let the user work on that feature without
managing a checkout per splice. Default branches need a mapping because
repositories can name them differently. Missing feature branches use the
default target for comparison, so inspection can show the prospective PR
before publication creates a branch
([push design](03-splicing-out.md#new-upstream-branches)).

Committed defaults and pins express a shared upstream choice; tracking
overrides express a developer's local workflow. Keeping the latter in Git
config avoids changing everyone's target to accommodate one checkout.
An explicit command-line choice takes precedence so a stored preference
does not prevent a deliberate one-off operation. A pin names an immutable
target, so it cannot be treated as a branch to publish to. The exact
selection rules belong with
[tracking](../03-concepts/01-upstreams.md#tracking-another-upstream-branch-locally)
and [pins](../09-scenarios/04-upstreams/06-default-pin/README.md).

Nested defaults come from the enclosing splice so the same committed
`.splice` has the same meaning when its upstream is cloned independently.
When a pin or differing enclosing defaults leave no unambiguous branch to
inherit, an explicit choice is needed rather than a guess
([nesting](../03-concepts/04-nesting.md#settings-come-from-the-splice-above)).
