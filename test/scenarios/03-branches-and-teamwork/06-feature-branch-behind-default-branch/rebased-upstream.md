# Rebase the PR upstream

In the [same state](README.md), rebase `feature` upstream too, in a
clone of the upstream, as "Update branch" with a rebase on GitHub does,
and pull that. The monorepo's `feature` is rebased already, so the
folder already has the rebased branch's files, and the pull only records
it as the synced commit. Without the monorepo's `git rebase main`, the
pull would bring *m* in.

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
>     rebase -q origin/main &&
>   git -C ../pr push -q --force origin feature
```

```scrut
$ git splice pull vendor/a
ok   vendor/a fetched (feature moved a35a3ef..e724c1a)
ok   vendor/a: recorded e724c1a as the synced commit -- the folder already has its files
```

```scrut
$ git splice status
On branch feature

  up to date  vendor/a
```
