# Changelog

## [0.2.0](https://github.com/roschaefer/git-splice/compare/v0.1.0...v0.2.0) (2026-10-06)


### Features

* nested splices whose inner .splice reaches the outer upstream ([#66](https://github.com/roschaefer/git-splice/issues/66)) ([7b65223](https://github.com/roschaefer/git-splice/commit/7b65223c339eaabc6d55dbe500bd48acedcaa68a)), closes [#48](https://github.com/roschaefer/git-splice/issues/48) [#5](https://github.com/roschaefer/git-splice/issues/5)

## 0.1.0 (2026-10-06)


### ⚠ BREAKING CHANGES

* fetched refs move from refs/splices/<escaped URL>/-/ to refs/splices/<key>/. Refs in the old layout are left behind; the next fetch fills the new one.
* .splice's splice.url is replaced by upstream.<name>.url. Every command refuses an old .splice and prints the git config commands that convert it. Refs fetched under the old layout aren't used; the next fetch fetches under the new keys, and the old refs/splices/<path>/ refs can be deleted.
* **status:** status prints counts in place of the diff stat, so scripts that parse its output need updating.
* replace git subtree with .splice state, URL fetches and an own rebuild ([#1](https://github.com/roschaefer/git-splice/issues/1))

### Features

* key fetched refs by short names mapped to upstream URLs ([#58](https://github.com/roschaefer/git-splice/issues/58)) ([1940555](https://github.com/roschaefer/git-splice/commit/1940555d96d6454843a5a9af0abe8f154077cc83))
* **log:** draw both sides as a graph with --graph, labeling R and T ([#63](https://github.com/roschaefer/git-splice/issues/63)) ([2bdf7b3](https://github.com/roschaefer/git-splice/commit/2bdf7b3cfe0c9fad71db272287d3faf27fb3b112))
* name upstreams in .splice, and key fetched refs by URL ([#47](https://github.com/roschaefer/git-splice/issues/47)) ([32eaabe](https://github.com/roschaefer/git-splice/commit/32eaabeefa5aa6e5e84862f1fb2cfbf1ed37a661))
* replace git subtree with .splice state, URL fetches and an own rebuild ([#1](https://github.com/roschaefer/git-splice/issues/1)) ([8554f98](https://github.com/roschaefer/git-splice/commit/8554f98534bf9c2581407c0970d0e7706a012906)), closes [#2](https://github.com/roschaefer/git-splice/issues/2)
* **status:** count commits like git status, and move the file summary to diff --stat ([#46](https://github.com/roschaefer/git-splice/issues/46)) ([caef453](https://github.com/roschaefer/git-splice/commit/caef45327d1419705fa1591ed423f6af92cd8a85)), closes [#39](https://github.com/roschaefer/git-splice/issues/39)
* **status:** warn about uncommitted changes in a splice's folder ([#45](https://github.com/roschaefer/git-splice/issues/45)) ([4dc295c](https://github.com/roschaefer/git-splice/commit/4dc295c3bf00caa6cd71d234ad5666186c026a54)), closes [#40](https://github.com/roschaefer/git-splice/issues/40)

## Changelog

git-splice continues [git-subtrees](https://github.com/roschaefer/git-subtrees),
whose last release was 0.1.2; see
[its changelog](https://github.com/roschaefer/git-subtrees/blob/main/CHANGELOG.md).
