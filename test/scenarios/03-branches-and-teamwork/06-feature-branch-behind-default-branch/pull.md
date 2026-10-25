# Pull the PR

In the [same state](README.md), a plain `pull` merges *f*, the old copy
of the feature change, back in. No change is lost: the folder keeps
*m*'s `lock.txt`. But the next push sends the feature change twice, the
rebased one and *f*, joined by the pull. A squash merge of the PR hides
that; a rebase merge doesn't. That's why `push` suggests
[`push --force`](push-force.md) here instead.

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
$ git splice pull vendor/a
ok   vendor/a fetched
ok   vendor/a: pulled a35a3ef
```

```scrut
$ cat vendor/a/lock.txt
bump dep
```

```scrut
$ git splice push vendor/a
ok   vendor/a: pushed c08925d to feature
```

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s feature
*   splice: pull vendor/a from feature at a35a3ef
|\  
| * feature change
* | feature change
* | bump dep
|/  
* seed
```
