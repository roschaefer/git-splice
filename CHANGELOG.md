# Changelog

## [0.8.1](https://github.com/roschaefer/git-splice/compare/v0.8.0...v0.8.1) (2026-10-15)


### Bug Fixes

* **fetch:** don't recurse into submodules when fetching an upstream ([#161](https://github.com/roschaefer/git-splice/issues/161)) ([6271d56](https://github.com/roschaefer/git-splice/commit/6271d56702d61338ba469f217905ffe66290028a)), closes [#162](https://github.com/roschaefer/git-splice/issues/162)

## [0.8.0](https://github.com/roschaefer/git-splice/compare/v0.7.0...v0.8.0) (2026-10-15)


### Features

* **clone:** --from-submodule --recursive converts nested submodules too ([#158](https://github.com/roschaefer/git-splice/issues/158)) ([66fcd54](https://github.com/roschaefer/git-splice/commit/66fcd545494c4790b5c17cad7ad2ff5bfe5466c2)), closes [#153](https://github.com/roschaefer/git-splice/issues/153)

## [0.7.0](https://github.com/roschaefer/git-splice/compare/v0.6.0...v0.7.0) (2026-10-15)


### ⚠ BREAKING CHANGES

* push, status and diff no longer take --base.

### Bug Fixes

* compare a missing upstream branch with upstream's default branch ([#152](https://github.com/roschaefer/git-splice/issues/152)) ([0bf6d7e](https://github.com/roschaefer/git-splice/commit/0bf6d7e0c3fae6cc6d6ddd6a2a80ad9b45fabf54)), closes [#150](https://github.com/roschaefer/git-splice/issues/150) [#3](https://github.com/roschaefer/git-splice/issues/3)

## [0.6.0](https://github.com/roschaefer/git-splice/compare/v0.5.0...v0.6.0) (2026-10-14)


### Features

* **clone:** --from-submodule turns a submodule into a splice ([#141](https://github.com/roschaefer/git-splice/issues/141)) ([5adf99d](https://github.com/roschaefer/git-splice/commit/5adf99d7423620e9d980f400b9d36ae8fd07c2d7))

## [0.5.0](https://github.com/roschaefer/git-splice/compare/v0.4.0...v0.5.0) (2026-10-14)


### ⚠ BREAKING CHANGES

* **boundary:** print the commit the rebuild starts from, and draw R after a pull ([#136](https://github.com/roschaefer/git-splice/issues/136))

### Features

* **boundary:** print the commit the rebuild starts from, and draw R after a pull ([#136](https://github.com/roschaefer/git-splice/issues/136)) ([081a8d6](https://github.com/roschaefer/git-splice/commit/081a8d6fea5e548378a292a7abe8f46c1bf811d9))

## [0.4.0](https://github.com/roschaefer/git-splice/compare/v0.3.0...v0.4.0) (2026-10-14)


### Features

* **push:** --force --rebuilt-commit may edit commits before the synced commit ([#132](https://github.com/roschaefer/git-splice/issues/132)) ([1ae8552](https://github.com/roschaefer/git-splice/commit/1ae8552291f688f14dfa2cd9179b15084e494ef2)), closes [#131](https://github.com/roschaefer/git-splice/issues/131)
* **push:** --rebuilt-commit, to push a rebuild whose history was edited ([#105](https://github.com/roschaefer/git-splice/issues/105)) ([87b4e0d](https://github.com/roschaefer/git-splice/commit/87b4e0d6f23ad9d21ea80cb94200f636dafb1c8f))

## [0.3.0](https://github.com/roschaefer/git-splice/compare/v0.2.0...v0.3.0) (2026-10-12)


### ⚠ BREAKING CHANGES

* a .splice with default-branch in [splice] is refused; move it to upstream.<name>.default-branch.
* **splice-file:** a `.splice` with `splice.url`, or without an id, is refused without printing how to convert it.
* a `.splice` without an id is refused.
* **rebuild:** the first push after `init` sends one commit, the init commit, instead of the folder's whole history.
* a nested `.splice` without `default-branch` that this monorepo wrote itself, where the nested upstream's default branch equals the monorepo's but not the outer upstream's, now follows the outer upstream's default branch. Set `default-branch` in it by hand to keep the old meaning.

### Features

* **boundary:** print a splice's boundary, the commit where it last synced ([#106](https://github.com/roschaefer/git-splice/issues/106)) ([e1df141](https://github.com/roschaefer/git-splice/commit/e1df141c7958d9703330844cc7443b1f9252c913)), closes [#100](https://github.com/roschaefer/git-splice/issues/100)
* give each splice an id, so a new URL keeps its history ([#79](https://github.com/roschaefer/git-splice/issues/79)) ([a9eab2b](https://github.com/roschaefer/git-splice/commit/a9eab2b6c165a0af271143a2cc4fc19fe5325bad)), closes [#78](https://github.com/roschaefer/git-splice/issues/78) [#96](https://github.com/roschaefer/git-splice/issues/96)
* **merge:** --bump, to move the sync point up to a push ([#116](https://github.com/roschaefer/git-splice/issues/116)) ([6d3013a](https://github.com/roschaefer/git-splice/commit/6d3013a0c966c3993d81d8d3188a5ad108ec412b))
* print a splice's rebuild, the commit push would send ([#103](https://github.com/roschaefer/git-splice/issues/103)) ([1dcb575](https://github.com/roschaefer/git-splice/commit/1dcb575ef9362d0db3f216fccf24e5e5c4e24fb8)), closes [#54](https://github.com/roschaefer/git-splice/issues/54)
* several upstreams per splice, chosen with --upstream ([#108](https://github.com/roschaefer/git-splice/issues/108)) ([230b169](https://github.com/roschaefer/git-splice/commit/230b16972fafa20f1ef92df20ae32ff75ef207e5))
* **status:** one aligned line per splice, the ones that need something first ([#118](https://github.com/roschaefer/git-splice/issues/118)) ([4bd5c1a](https://github.com/roschaefer/git-splice/commit/4bd5c1abb83f69129ce9fa5941342f5adf94a980))


### Bug Fixes

* a nested splice without default-branch follows the splice above ([#89](https://github.com/roschaefer/git-splice/issues/89)) ([13d9a7d](https://github.com/roschaefer/git-splice/commit/13d9a7d58060798ddf0acf6babff8d7ca93dd7c7))
* **merge:** record an upstream with the same files as the synced commit ([#92](https://github.com/roschaefer/git-splice/issues/92)) ([c0e8334](https://github.com/roschaefer/git-splice/commit/c0e8334303d091fdac91ef8fa71089055648b1d9)), closes [#17](https://github.com/roschaefer/git-splice/issues/17)
* **rebuild:** find a splice's boundary and mount with log.showSignature ([#111](https://github.com/roschaefer/git-splice/issues/111)) ([eb8849b](https://github.com/roschaefer/git-splice/commit/eb8849b89ca18a6093bdb12bf3c228bb4d40658f))
* **rebuild:** never publish history from before a folder was this splice ([#77](https://github.com/roschaefer/git-splice/issues/77)) ([a22854c](https://github.com/roschaefer/git-splice/commit/a22854c45973dd34a60dab8ed550539787cecb6a)), closes [#73](https://github.com/roschaefer/git-splice/issues/73) [#18](https://github.com/roschaefer/git-splice/issues/18)
* **rebuild:** take a nested splice's history before the outer boundary from the outer upstream ([#83](https://github.com/roschaefer/git-splice/issues/83)) ([89b294b](https://github.com/roschaefer/git-splice/commit/89b294b6e49688f7e662a86526f874b7927d1c17)), closes [#74](https://github.com/roschaefer/git-splice/issues/74)


### Performance Improvements

* **rebuild:** read a splice's id once in the mount walk ([#98](https://github.com/roschaefer/git-splice/issues/98)) ([83f1f25](https://github.com/roschaefer/git-splice/commit/83f1f253f2bb595bed980aa357f1496dd521395e))


### Code Refactoring

* **splice-file:** stop reading formats of earlier versions ([#97](https://github.com/roschaefer/git-splice/issues/97)) ([5e91c1c](https://github.com/roschaefer/git-splice/commit/5e91c1c0f3177e87212ff0bc0a06003d2ac97863))

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
