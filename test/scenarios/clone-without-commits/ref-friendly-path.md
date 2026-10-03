# Scenario: a splice path must be ref-friendly

A splice path becomes part of `refs/splices/<path>/<branch>`. Git ref names
cannot contain spaces, so `git splice clone` rejects such a path before it
fetches anything.

## Output

`scenario_clone_without_commits` in [`setup.bash`](setup.bash) builds the
same empty monorepo used by the other document in this folder. The first
command gives it the commit this independent example needs. [How scenarios
work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_clone_without_commits
```
-->

```scrut
$ git commit -q --allow-empty -m "initial commit" && git splice clone "$UPSTREAM" "my lib"
!!   'my lib' can't be part of a Git ref name, so it can't be a splice -- choose another folder name (e.g. no spaces)
[1]
```

No splice refs were created:

```scrut
$ git for-each-ref --format='%(refname)' refs/splices
```
