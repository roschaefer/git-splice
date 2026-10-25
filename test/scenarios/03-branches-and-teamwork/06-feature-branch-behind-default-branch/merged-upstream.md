# Merge main into the PR upstream

In the [same state](README.md), as with a [rebase
upstream](rebased-upstream.md), but `main` is merged into `feature` in
a clone of the upstream, as "Update branch" with a merge on GitHub does.
The folder already has the merge's files, so the pull only records it
as the synced commit.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_feature_branch_behind_default_branch
```

```scrut
$ git clone -q -b feature "$UPSTREAM" ../pr &&
>   git -C ../pr -c user.name=Maintainer -c user.email=maintainer@example.com \
>     merge -q --no-edit origin/main &&
>   git -C ../pr push -q origin feature
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (feature moved a35a3ef..df5294a)
ok   vendor/a: recorded df5294a as the synced commit -- the folder already has its files
```

```scrut
$ git splice status
On branch feature

  up to date  vendor/a
```
