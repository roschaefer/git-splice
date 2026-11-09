# State and upstreams

The [architecture overview](README.md#architecture) separates committed
splice state from local fetched refs. This page explains the storage choices.

## The `.splice` file

[The `.splice` file](../03-concepts/README.md) shows
what it holds and which commands write it, and why it has no path and no
monorepo commit. The other choices:

- **Git's config format, read and written by Git.** There's no parser of
  our own, and the file is never sourced, since that would run whatever
  someone commits into it.
- **Its name** clashes with no known configuration file, so build or
  package globs that see it in the monorepo don't mistake it for theirs.
- **Its `id` is derived, not random,** from the path, `HEAD`, the
  upstream's URL and, for `clone`, the commit it splices in. So a command
  gives the same result each time it runs on the same commit, while two
  splices of different upstreams mounted at the same path on branches
  from the same commit still get different ids. The rebuild uses it to
  tell this splice from another one that had the same path before
  ([push design](03-splicing-out.md#splicing-out-push-and-the-rebuild)).
- **`default-branch` is recorded once**, by `clone` and `init`, and only
  when it differs. That keeps it stable if the upstream later renames its
  default branch, and visible to anyone wondering why `main` syncs with
  `master`. It belongs to the upstream, like its URL: a company fork may
  name its default branch differently from the original. Where the
  splice above leaves it open, commands refuse rather than fall back to
  the monorepo's.
- **No merge driver** for the conflict two pulling branches get. One can
  follow if that turns out to be common.

## Refs instead of remotes

Upstream branches are fetched by URL into private refs:

```
git fetch --prune --no-tags <url> '+refs/heads/*:refs/splices/<key>/heads/*'
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
the `git config` command that fixes it. A key has no `/`, so it ends
right before `heads/`, and branch names, which may have one, follow that. `git splice key <path>` prints a splice's key, and
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
  [Why that matters](04-safety-and-limits.md).
- `url.<base>.insteadOf` and `pushInsteadOf` still apply, since they work
  on URLs.
- `push` goes to the URL, and then updates `refs/splices/<key>/heads/<branch>`
  itself. If it can't, the push counts as failed.
- `--prune` drops branches deleted upstream, so no `prune` command is
  needed.
- Every Git command can read an upstream as `splices/<key>/heads/<branch>`,
  as of the last fetch, so no separate clone is needed
  ([looking at an upstream](../06-command-reference/02-fetch.md#looking-at-an-upstream)).

Two rules follow from the layout:

- **Both sides of a [nested splice](../03-concepts/04-nesting.md)
  find the same state.** The `.splice` holds nothing specific to the
  monorepo, and fetched refs are keyed by URL, so the monorepo and the
  upstream above find the same synced commit under the same refs. An
  upstream with a `.splice` at its root is refused: it would replace the
  splice's own.
- **A splice's path must work in a ref name** (`git check-ref-format`),
  which applies to the whole path: no spaces, no component ending in
  `.lock`, and so on.

## Branches

- Each splice syncs with the upstream branch named like the monorepo's
  current branch, for every command. Switching branches switches every
  splice.
- The monorepo's default branch maps to upstream's default branch
  (the upstream's `default-branch` in `.splice` if the names differ). Every other branch
  keeps its name on both sides.
- The monorepo's default branch is `origin/HEAD`, else
  `init.defaultBranch`.
- If upstream has no branch named like the current one, every command
  compares with upstream's default branch instead, as a PR from that
  branch would, and `push` creates it only as described
  [in the push design](03-splicing-out.md#splicing-out-push-and-the-rebuild). Which branch it was cut
  from doesn't matter: Git doesn't record it, and commits from there
  that upstream lacks have to get there somehow, e.g. through a PR.
