# Scenario: `git subtree` preserves a monorepo merge

Two lines of work under the splice, joined by a merge in the monorepo.

- **Monorepo (`vendor/a`)**: cloned at `seed`. `main` and `feature` each
  committed under `vendor/a`, then `main` was merged into `feature`, and
  `feature` committed again.
- **Upstream**: `seed` only.

[`git subtree split`](https://github.com/git/git/blob/master/contrib/subtree/git-subtree.adoc#split-local-commit-repository)
translates every commit that affected the folder, including the side branch
and merge. `git splice` follows first parents from its recorded sync point
instead. The merge becomes one ordinary upstream commit carrying `main`'s
content; the monorepo's private branch topology is not published.

## Output

<!--
```scrut {fail_fast: true, output_stream: combined}
$ source "$TESTDIR/../../../readme-setup.sh"
```
-->

[`setup.bash`](setup.bash) builds this state:

```scrut
$ build_scenario scenario_merge_in_monorepo
```

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

`git subtree split` preserves the graph:

```scrut
$ git subtree split --quiet --prefix=vendor/a --branch subtree-result >/dev/null && echo "created subtree-result"
created subtree-result
```

```scrut
$ git log --graph --format=%s subtree-result | sed 's/ *$//'
* after the merge
*   Merge branch 'main' into feature
|\
| * main work
* | feature work
|/
* add vendor/a
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

The two results contain the same files, but deliberately not the same
history shape.
