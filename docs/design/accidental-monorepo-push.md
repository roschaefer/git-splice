# Accidentally pushing the monorepo to a subfolder's remote

`git splice` has no Git remotes for its upstreams. This document explains
why: a remote that points to a subfolder's repository is one mistyped
command away from publishing the whole monorepo. It was written in
October 2026, while the predecessor of `git splice` still kept one Git
remote per `git subtree`.

A subtree remote is an ordinary Git remote. Any push to it that isn't a
`git subtree split` sends the **whole monorepo history** there, including
folders that may never be meant to leave it. This affects everyone who uses
`git subtree`.

It's a slip of the fingers, but it's hard to undo: deleting the branch
afterwards doesn't unpublish anything. GitHub keeps the commits reachable
by SHA until support purges them, and anyone who fetched or forked in the
meantime has a copy
([an example with ~4000 commits pushed by mistake](https://github.com/orgs/community/discussions/21995)).
So this shouldn't be left to the user being careful.

## How the monorepo ends up on a subtree remote

Typing `git push vendor/foo main` by mistake is the obvious way, but not
the only one. These cases were checked with Git 2.55 on a monorepo with a
subtree `vendor/a`:

- **`push.autoSetupRemote` on a repo whose only remote is a subtree
  remote.** A plain `git push` on a new branch picks the only remote,
  pushes the monorepo there and makes it the upstream:

  ```
  $ git config push.autoSetupRemote true
  $ git switch -c topic && git push
   * [new branch]      topic -> topic
  branch 'topic' set up to track 'vendor/a/topic'.
  ```

  A monorepo without `origin` (e.g. local-only, publishing parts of itself)
  is exactly the setup where this happens.
- **Once a branch's upstream is a subtree remote**, every later plain
  `git push`, the IDE's "Sync" button or LazyGit's `P` goes there. Besides
  `push.autoSetupRemote` and `git push -u`, `remote.pushDefault` and
  `branch.<name>.pushRemote` can point there too. `git switch <name>` also
  creates a branch tracking a subtree remote when only that remote has a
  branch `<name>`.
- **LazyGit**, for a branch without an upstream, suggests `origin` if it
  exists and otherwise the first remote
  ([`getSuggestedRemote`](https://github.com/jesseduffield/lazygit/blob/master/pkg/gui/controllers/helpers/upstream_helper.go)).
  Without `origin`, a subtree remote is one Enter away. With
  `push.default=current` it doesn't ask at all.
- **Shell history.** `git push vendor/a main` and
  `git subtree push --prefix=vendor/a vendor/a main` both match a reverse
  search for `push vendor/a`.
- `git push --all <remote>` and `git push --mirror <remote>`.

When the remote already has the branch, a plain push is usually rejected
as non-fast-forward. The dangerous cases are **new branches** and
**`--force`**.

## Options that keep the remotes

These assume a wrapper around `git subtree` that names each remote like
its folder and pushes with `git subtree push`.

### 1. A pre-push hook that checks content

The wrapper installs a `pre-push` hook that refuses any pushed commit that
has a folder named like the remote it's pushed to: if remote names equal
folder paths, that's a monorepo commit. It works for plain, forced, by-SHA
and new-branch pushes, and leaves `git subtree push` and a pushed
`git subtree split -b` branch alone.

Limits:

- Hooks aren't cloned: every clone needs to install it.
- `git push --no-verify` skips it.
- It competes with hook managers (husky, lefthook, pre-commit) for
  `pre-push` / `core.hooksPath`.
- A false alarm when a subtree has a folder named like its own path
  (`lib/lib/`).

### 2. A push URL that can't be pushed to

The well-known trick for a fetch-only remote is
`git remote set-url --push <remote> no_push`
([e.g.](https://drake.mit.edu/no_push_to_origin.html)). The wrapper would
then push to the fetch URL explicitly:
`git subtree push --prefix=<path> <fetch-url> <branch>`.

- `--no-verify` doesn't get past it, and no hook is needed.
- Pushing to a URL doesn't update `refs/remotes/<remote>/*`, which a status
  command relies on, so the wrapper's push must update them itself (or
  fetch).
- Plain `git subtree push <remote>` is blocked too. Users would have to
  pass the URL.
- The error is confusing: `'no_push' does not appear to be a git
  repository`.
- Like hooks, remote config isn't cloned. But remotes are added per clone
  anyway, and the wrapper could set it.
- Tools that read the push URL to find out which repository a remote
  points to can break. The VS Code GitHub Actions extension stops showing
  workflows when `pushurl` is invalid
  ([github/vscode-github-actions#298](https://github.com/github/vscode-github-actions/issues/298),
  open since March 2024).

### 3. A custom remote protocol that marks the remote

Git runs `git-remote-<scheme>` for a URL `<scheme>::<address>`
([gitremote-helpers](https://git-scm.com/docs/gitremote-helpers)). The
wrapper could ship a `git-remote-guard` helper and mark protected remotes
with it. There are two variants, both prototyped locally:

- **Push URL only:** `git remote set-url --push vendor/a guard::<url>`.
  The helper only refuses, with a clear message. The wrapper pushes to the
  fetch URL, as in option 2.

  ```
  $ git push vendor/a main:x
  !!   'vendor/a' is a subtree remote -- push it with the wrapper, not 'git push'
  fatal: remote helper 'guard' aborted session
  ```

  Unlike the hook, `--no-verify` doesn't skip it.
- **Fetch and push URL:** `url = guard::<url>`. The helper declares the
  `connect` capability, runs `git-upload-pack` for fetches, and refuses
  `git-receive-pack` unless the wrapper's push set an environment
  variable. The push then goes through the remote name, so tracking refs
  stay current. This works for local paths. For ssh, the helper has to run
  `ssh <host> git-upload-pack <path>` itself. For https, `connect` doesn't
  exist, so the helper would have to proxy `git remote-https` and watch for
  `list for-push`/`push` commands. That's much more work and more fragile.

Concerns:

- The helper must be on the `PATH` of every program that runs Git (GUIs,
  IDEs). Otherwise Git fails with `'remote-guard' is not a git command`.
  That fails closed, but it's confusing.
- Tools that read remote URLs (`gh`, LazyGit's "open in browser", IDEs)
  may not understand `guard::…`. The push-URL-only variant keeps the fetch
  URL readable.
- Protocols other than the built-in ones fall under `protocol.allow`'s
  default policy `user`. That's fine for interactive use, but Git sets
  `GIT_PROTOCOL_FROM_USER=0` for submodule operations, which then refuses
  them.
- Prior art:
  [sethfowler/git-remote-subtree](https://github.com/sethfowler/git-remote-subtree)
  wanted a remote helper that maps a subtree to a remote
  (`subtree::<dir>::on::<branch>::from::<url>`). It was never finished.

### 4. On the server

A server-side rule on the subtree's repository (e.g. GitHub push rulesets
that restrict file paths) would hold no matter which client pushes. Still
open: whether push rulesets are available for the repositories and plans
this matters for (public repositories in particular), and whether a rule
can be phrased without knowing the monorepo's folder names.

## Prior art: exporting parts of a private monorepo

Large companies publish parts of private monorepos all the time, but not
with `git subtree`. Google uses [Copybara](https://github.com/google/copybara)
(`PiperOrigin-RevId:` trailers on ~31M public commits; Copybara's default
`GitOrigin-RevId:` on ~4.8M more), Meta uses
[ShipIt](https://github.com/facebook/fbshipit) (`fbshipit-source-id:`).
Their setups share a structure:

- The public repository is an export of the monorepo, generated by a bot
  with its own credentials. Developers' clones have no push access to it,
  often no remote for it, so there is nothing to mistype.
- An allowlist decides what leaves (Copybara's
  `origin_files = glob([...])`, ShipIt's path mappings), and lines marked
  internal-only can be stripped.
- Commit messages and authors can be rewritten on the way out.
- External PRs are imported, reviewed and merged in the monorepo, then
  exported back. The PR is closed, not merged, e.g.
  [abseil-cpp#2087](https://github.com/abseil/abseil-cpp/pull/2087): the
  commit on `master` is a new, single-parent commit with the contributor as
  author and `Copybara-Service` as committer.

Small setups are invisible from the outside: a correct `git subtree split`
leaves no trace in the public repository, so we can't tell how others with
a private monorepo avoid this, or how often it goes wrong.

## What `git splice` does instead

Like the large exporters, `git splice` leaves nothing to mistype: Git
remotes should only point to repositories of the whole monorepo, never to
a subfolder's. Upstreams are fetched and pushed by URL, from the committed
`.splice` file, into private refs
([Refs instead of remotes](README.md#refs-instead-of-remotes)):

- With no remote, `push.autoSetupRemote`, `remote.pushDefault`, tracking
  branches, `git switch <name>`, LazyGit's suggestion, `--all` and
  `--mirror` have no subfolder repository to pick.
- `git push vendor/a main` fails, because `vendor/a` is neither a remote
  nor a repository.
- Nothing needs installing per clone, `--no-verify` has nothing to skip,
  and no tool sees an invalid or unusual URL.
- `git splice push` updates `refs/splices/<key>/<branch>` itself, so
  `status` stays current without tracking refs.

What remains is typing an upstream's URL into a plain `git push` by hand,
which is hard to do by accident.
