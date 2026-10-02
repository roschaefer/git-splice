# Scenario: clone-on-feature-branch

Cloning while on a branch upstream doesn't have.

- **Monorepo**: on `feature`.
- **Upstream**: only `main`.

`clone` takes upstream's default branch instead. The first push creates
`feature` upstream, if the splice changed by then.

## Output

`scenario_clone_on_feature_branch` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_clone_on_feature_branch
```
-->

```scrut
$ git splice clone "$UPSTREAM" vendor/a
===  vendor/a: fetching $UPSTREAM
===  vendor/a: upstream has no 'feature' branch -- using 'main'; your first push creates 'feature'
ok   vendor/a: cloned bde4164 from main
```

```scrut
$ git splice status
ok   vendor/a -> feature (upstream has no such branch; changed since 'main' -- push would create it)
 file.txt | 1 +
 1 file changed, 1 insertion(+)
```
