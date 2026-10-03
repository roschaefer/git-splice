# Scenario: `main` is merged into a feature branch repeatedly

The same monorepo lines of work can meet more than once. This example starts
with the merge from the folder's base scenario, then changes `main`, merges
it into `feature` a second time, and adds one more feature commit.

`git subtree split` retains both merge edges and all commits from `main`.
`git splice` emits the first-parent story: each merge is one ordinary commit
whose tree includes the newly merged content.

## Output

`scenario_merge_in_monorepo` and `merge_main_into_feature_again` in
[`setup.bash`](setup.bash) build this state. [How scenarios
work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_merge_in_monorepo && merge_main_into_feature_again "$PWD"
```
-->

The monorepo contains two merges from `main`:

```scrut
$ git log --graph --format=%s | sed 's/ *$//'
* after the second merge
*   Merge branch 'main' into feature
|\
| * second main work
* | after the merge
* | Merge branch 'main' into feature
|\|
| * main work
* | feature work
|/
* add vendor/a
* initial commit
```

```scrut
$ git subtree split --quiet --prefix=vendor/a --branch subtree-result >/dev/null && echo "created subtree-result"
created subtree-result
```

```scrut
$ git log --graph --format=%s subtree-result | sed 's/ *$//'
* after the second merge
*   Merge branch 'main' into feature
|\
| * second main work
* | after the merge
* | Merge branch 'main' into feature
|\|
| * main work
* | feature work
|/
* add vendor/a
```

The splice rebuild is linear even after repeated merges:

```scrut
$ git splice push vendor/a
??   vendor/a: upstream has no 'feature' branch yet -- this push creates it (changed since 'main')
ok   vendor/a: pushed d3cbcfa to feature
```

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s feature
* after the second merge
* Merge branch 'main' into feature
* after the merge
* Merge branch 'main' into feature
* feature work
* seed
```
