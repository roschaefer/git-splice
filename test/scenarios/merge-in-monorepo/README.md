# Scenario: merge-in-monorepo

Two lines of work under the splice, joined by a merge in the monorepo.

- **Monorepo (`vendor/a`)**: cloned at `seed`. `main` and `feature` each
  committed under `vendor/a`, then `main` was merged into `feature`, and
  `feature` committed again.
- **Upstream**: `seed` only.

The rebuild follows first parents: the merge becomes one ordinary commit
that carries `main`'s change, and `main work` isn't published as a commit
of its own. Upstream doesn't know the monorepo's side branches, so their
shape adds nothing there. `git subtree split` would keep the merge; this is
an approved divergence from it.

## Output

`scenario_merge_in_monorepo` in [`setup.bash`](setup.bash)
builds this state. [How scenarios work](../README.md).

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../readme-setup.sh" && build_scenario scenario_merge_in_monorepo
```
-->

```scrut
$ git log --graph --format=%s
* after the merge
*   Merge branch 'main' into feature
|\  
| * main work
* | feature work
|/  
* add vendor/a
* initial commit
```

```scrut
$ git splice log
===  vendor/a (upstream has no 'feature' branch)
< 6648f65 after the merge  (Test <test@example.com>)
< 0a72413 Merge branch 'main' into feature  (Test <test@example.com>)
< 8525688 feature work  (Test <test@example.com>)
```

```scrut
$ git splice push vendor/a
??   vendor/a: upstream has no 'feature' branch yet -- this push creates it (changed since 'main')
ok   vendor/a: pushed 6648f65 to feature
```

```scrut
$ git -C "$UPSTREAM" log --graph --format=%s feature
* after the merge
* Merge branch 'main' into feature
* feature work
* seed
```
