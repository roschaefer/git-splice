# Limits

These are current restrictions and workarounds. Reproductions and unresolved
bugs are documented in [Scenarios](../09-scenarios/README.md) and
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
