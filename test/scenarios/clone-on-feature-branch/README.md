# Scenario: clone-on-feature-branch

Cloning while on a branch upstream doesn't have.

- **Monorepo**: on `feature`.
- **Upstream**: only `main`.

`clone` takes upstream's default branch instead. `feature` comes upstream
with the first push that has a commit for it, e.g. after a change on
`feature`.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_clone_on_feature_branch
```

```scrut
$ git splice clone "$UPSTREAM" vendor/a
===  vendor/a: fetching $UPSTREAM
===  vendor/a: upstream has no 'feature' branch -- using 'main'; your first push creates 'feature'
ok   vendor/a: cloned bde4164 from main
```

```scrut
$ git splice status
On branch feature

  unchanged, no upstream branch  vendor/a
```
