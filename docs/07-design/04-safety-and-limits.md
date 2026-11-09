# Safety and limits

## Accidentally pushing the monorepo to a subfolder's remote

A Git remote for a subfolder's repository can receive the whole monorepo
history. A normal `git push` does not know that only a folder should leave.
New branches and forced pushes are especially dangerous: a non-fast-forward
rejection does not protect them.

It need not be an explicit `git push vendor/a main`. A branch can start
tracking that remote, after which a plain push or an IDE's sync action
uses it. Deleting the branch afterwards cannot retract copies already
fetched. The design should not depend on every user choosing correctly.

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

### What git-splice does instead

Upstreams are fetched and pushed by URL from `.splice`, using
[private refs](01-state-and-upstreams.md#refs-instead-of-remotes).
Git's remote selection, branch tracking and GUI remote pickers therefore
have no subfolder remote to choose. No hook, helper or unusual URL is
required in each clone. A plain `git push vendor/a main` fails because
`vendor/a/` is neither a remote nor a repository.

`git splice push` updates its fetched ref after publishing. Typing the
upstream URL into a plain Git push remains possible: this design removes
accidental remote selection, not Git's ability to push by URL.

The rebuild also limits what the intended push publishes: the splice's
own history begins at its [mount](03-splicing-out.md#history-scope).
It excludes the folder's history before `init` and follows splice identity
across moves, so another splice's old history is not treated as its own.

For the different tradeoffs of a centrally operated export pipeline, see
[Copybara and ShipIt](../05-comparisons/02-third-party/04-export-tools.md).

## Limits

These restrictions keep the design bounded. Reproductions and unresolved
bugs belong in [Scenarios](../09-scenarios/README.md) and
[Known bugs](../09-scenarios/99-known-bugs.md).

- **Nested pulls can conflict.** If both the monorepo and the enclosing
  upstream independently pull the inner splice, the next outer pull can
  conflict there. Push the enclosing splice after the inner pull to
  publish that state, rather than pulling it independently on both sides
  ([nested splices](../09-scenarios/05-nested-splices/01-nested-splices/README.md)).
  If there are no unpushed inner changes, keeping the enclosing upstream's
  version is an option when resolving the conflict.
- **Upstream gitlinks remain unsupported.** Converting submodules with
  `clone --from-submodule --recursive` does not teach later pulls to follow
  upstream commits that move those gitlinks
  ([clone](../06-command-reference/01-clone.md#--recursive),
  [#153](https://github.com/roschaefer/git-splice/issues/153)).
- **Paths must be valid in Git ref names.** Spaces and components ending
  in `.lock`, for example, are refused.
- **Paths and commit identities must be valid UTF-8.** The repository
  path, splice paths, arguments and rebuilt author/committer identities
  must cross the process boundary consistently on every platform.
  Commit messages can contain arbitrary bytes. Unsupported names need
  renaming or rewriting before they reach a shared branch.
- **No pager on Windows.** `log` and `diff` print directly; pipe them to a
  pager if needed.
- **An unrecorded sync point costs more to rebuild.** Before `init` has a
  recorded synced commit, rebuilding starts at the init commit.
  [`pull --bump`](../04-advanced-workflows/03-bump.md) can advance the
  boundary after publishing.

Rare cases are tracked with the
[`edge case`](https://github.com/roschaefer/git-splice/issues?q=label%3A%22edge+case%22)
label rather than expanding the ordinary workflow for every possibility.
