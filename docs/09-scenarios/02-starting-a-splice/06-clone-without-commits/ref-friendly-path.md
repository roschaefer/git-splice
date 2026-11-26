# Scenario: a splice path must be ref-friendly

A splice path must be valid in a Git ref name, e.g. without spaces, so
`git splice clone` rejects such a path before it fetches anything.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds the same empty monorepo as the other
document in this folder:

```scrut
$ build_scenario scenario_clone_without_commits
```

The first command gives it the commit this example needs:

```scrut
$ git commit -q --allow-empty -m "initial commit" && git splice clone "$UPSTREAM" "my lib"
!!   'my lib' isn't supported as a splice path yet -- choose another folder name (e.g. no spaces)
[1]
```

No splice refs were created:

```scrut
$ git for-each-ref --format='%(refname)' refs/splices
```
