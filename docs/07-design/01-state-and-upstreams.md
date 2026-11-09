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

The candidate names are `lib`, `x-lib`, then `github.com-x-lib`; a numeric
suffix resolves remaining collisions. Keys are lower-case, ref-safe and
at most 64 characters. Allocation takes a lock so simultaneous fetches
cannot claim the same key. Conflicting or invalid hand-edited mappings
are refused.

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

The monorepo's default branch is `origin/HEAD`, falling back to
`init.defaultBranch`. Ordinarily it maps to the upstream's default branch,
and other branches keep the same name on both sides.

Two explicit choices override that mapping: `--branch` selects a target
for the command, and `--track` stores a branch-to-upstream-key mapping in
local Git config for later commands. `--branch` takes precedence over the
stored tracking choice. Without either override, a committed `default-pin`
selects a tag or commit on the default branch and refuses a push there;
feature branches still follow named upstream branches. See
[tracking](../03-concepts/01-upstreams.md#tracking-another-upstream-branch-locally)
and [pins](../09-scenarios/04-upstreams/06-default-pin/README.md).

If an ordinary feature branch does not exist upstream, comparison uses
the upstream's default target, as a PR would. A push creates the branch
only if it has commits the default target lacks
([push design](03-splicing-out.md#new-upstream-branches)).

A nested splice inherits an unspecified default branch from its enclosing
splice, so its `.splice` means the same in a clone of that upstream.
An enclosing pin requires a `default-branch` below it. Differing defaults
among enclosing upstreams need a chosen upstream or an explicit default
branch ([nesting](../03-concepts/04-nesting.md#settings-come-from-the-splice-above)).
