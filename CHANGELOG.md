# Changelog

## [0.16.2](https://github.com/roschaefer/git-splice/compare/v0.16.1...v0.16.2) (2026-10-29)


### Bug Fixes

* **state:** read a .splice key without a value as empty ([#194](https://github.com/roschaefer/git-splice/issues/194)) ([8288a75](https://github.com/roschaefer/git-splice/commit/8288a7534788ff37e03eec15415b5b511fe93975))

## [0.16.1](https://github.com/roschaefer/git-splice/compare/v0.16.0...v0.16.1) (2026-10-29)


### Bug Fixes

* **clone:** refuse to splice a submodule that update = none keeps out of checkouts ([#303](https://github.com/roschaefer/git-splice/issues/303)) ([7252f07](https://github.com/roschaefer/git-splice/commit/7252f07dbca1f66f5a1ebceb6898d2d3415563cc))
* **rebuild:** follow git mv, so a move keeps unpushed commits ([#24](https://github.com/roschaefer/git-splice/issues/24)) ([7f1003d](https://github.com/roschaefer/git-splice/commit/7f1003db981d039966200d6f4c2401b57e2fb02c)), closes [#4](https://github.com/roschaefer/git-splice/issues/4) [#187](https://github.com/roschaefer/git-splice/issues/187)

## [0.16.0](https://github.com/roschaefer/git-splice/compare/v0.15.0...v0.16.0) (2026-10-28)


### Features

* --track an upstream branch per monorepo branch, like git push -u ([#292](https://github.com/roschaefer/git-splice/issues/292)) ([315a805](https://github.com/roschaefer/git-splice/commit/315a8051810974a2f7cfe5e2f0ea241b304a3054)), closes [#289](https://github.com/roschaefer/git-splice/issues/289)
* **push:** --branch pushes to another upstream branch, like pull --branch ([#291](https://github.com/roschaefer/git-splice/issues/291)) ([eec593f](https://github.com/roschaefer/git-splice/commit/eec593fc3ccc8a4039deef4fae2732d28156f9ac)), closes [#290](https://github.com/roschaefer/git-splice/issues/290)

## [0.15.0](https://github.com/roschaefer/git-splice/compare/v0.14.2...v0.15.0) (2026-10-28)


### Features

* **help:** structure command reference output ([#282](https://github.com/roschaefer/git-splice/issues/282)) ([7ef6a04](https://github.com/roschaefer/git-splice/commit/7ef6a04ec7eabbca2aea1cd48780e438c3225546))


### Bug Fixes

* **status:** unchanged when a PR would show no changes ([#286](https://github.com/roschaefer/git-splice/issues/286)) ([7f031d6](https://github.com/roschaefer/git-splice/commit/7f031d66542ef311e4b502d6c209898c061c8026)), closes [#285](https://github.com/roschaefer/git-splice/issues/285)

## [0.14.2](https://github.com/roschaefer/git-splice/compare/v0.14.1...v0.14.2) (2026-10-27)


### Bug Fixes

* **pull:** --rebase states only that the reflog lacks the synced commit ([#263](https://github.com/roschaefer/git-splice/issues/263)) ([cd2dcb3](https://github.com/roschaefer/git-splice/commit/cd2dcb3112231a9fd923a1181dc12e6f409c99c3)), closes [#256](https://github.com/roschaefer/git-splice/issues/256)

## [0.14.1](https://github.com/roschaefer/git-splice/compare/v0.14.0...v0.14.1) (2026-10-27)


### Bug Fixes

* a step that fails stops the command, instead of a wrong rebuild ([#261](https://github.com/roschaefer/git-splice/issues/261)) ([ffa5f3c](https://github.com/roschaefer/git-splice/commit/ffa5f3c9cc962957c7508d9904b2b5b39c2d2bc0)), closes [#12](https://github.com/roschaefer/git-splice/issues/12)

## [0.14.0](https://github.com/roschaefer/git-splice/compare/v0.13.0...v0.14.0) (2026-10-26)


### Features

* **drawings:** check each picture is its diagram's export; serve it plain ([#259](https://github.com/roschaefer/git-splice/issues/259)) ([f4a23c1](https://github.com/roschaefer/git-splice/commit/f4a23c15a9af6816f6639534407d450f53cf39df)), closes [#171](https://github.com/roschaefer/git-splice/issues/171) [#258](https://github.com/roschaefer/git-splice/issues/258)


### Bug Fixes

* a synced commit that isn't here asks for a fetch, not to pick a side ([#257](https://github.com/roschaefer/git-splice/issues/257)) ([31db1e1](https://github.com/roschaefer/git-splice/commit/31db1e1d626ffb16c634732549a0aafb10c030c7)), closes [#67](https://github.com/roschaefer/git-splice/issues/67)
* **deps:** update svgo to v4 ([#262](https://github.com/roschaefer/git-splice/issues/262)) ([d02c833](https://github.com/roschaefer/git-splice/commit/d02c833f9813a4f78bdfc2c9a6286bb9945f73a2))

## [0.13.0](https://github.com/roschaefer/git-splice/compare/v0.12.0...v0.13.0) (2026-10-26)


### Features

* -m &lt;message&gt; for the commits clone, init, merge and pull write ([#246](https://github.com/roschaefer/git-splice/issues/246)) ([4747d63](https://github.com/roschaefer/git-splice/commit/4747d634c3ec5d7f9e27d4f1a244dbce7b20bd6b)), closes [#244](https://github.com/roschaefer/git-splice/issues/244)


### Bug Fixes

* **pull:** --rebase refuses to drop the default branch's commits ([#238](https://github.com/roschaefer/git-splice/issues/238)) ([818d297](https://github.com/roschaefer/git-splice/commit/818d297ed1374fcabdf0a22cc08e94811f5fd706)), closes [#236](https://github.com/roschaefer/git-splice/issues/236)

## [0.12.0](https://github.com/roschaefer/git-splice/compare/v0.11.0...v0.12.0) (2026-10-24)


### ⚠ BREAKING CHANGES

* **clone:** --from-submodule keeps what the submodule followed ([#233](https://github.com/roschaefer/git-splice/issues/233))
* **fetch:** keep fetched branches under refs/splices/<key>/heads/ ([#230](https://github.com/roschaefer/git-splice/issues/230))

### Features

* **clone:** --from-submodule keeps what the submodule followed ([#233](https://github.com/roschaefer/git-splice/issues/233)) ([6679ce0](https://github.com/roschaefer/git-splice/commit/6679ce04954e5fd9f25bc8bacffedca64fc2d2af))
* pin a splice to a tag or a commit with default-pin ([#232](https://github.com/roschaefer/git-splice/issues/232)) ([7ad7478](https://github.com/roschaefer/git-splice/commit/7ad7478b312c33723b9931a9b9967b41f37fa50b))
* **sandbox:** open any docs page in a sandbox, the walkthrough by default ([#234](https://github.com/roschaefer/git-splice/issues/234)) ([6a16d0e](https://github.com/roschaefer/git-splice/commit/6a16d0ef1fb239e395938af6cea4e1d74e04d3e0))
* **website:** search the docs with a local full-text index ([#226](https://github.com/roschaefer/git-splice/issues/226)) ([0cc2560](https://github.com/roschaefer/git-splice/commit/0cc25604510b48e8a0e9771a47d6d314a3ace272))


### Code Refactoring

* **fetch:** keep fetched branches under refs/splices/&lt;key&gt;/heads/ ([#230](https://github.com/roschaefer/git-splice/issues/230)) ([1f4890a](https://github.com/roschaefer/git-splice/commit/1f4890aaa2d551c3d8e95b60e1bfa8c2ea2d5b92))

## [0.11.0](https://github.com/roschaefer/git-splice/compare/v0.10.0...v0.11.0) (2026-10-22)


### Features

* **pull:** rebase local splice changes onto the upstream with --rebase ([#208](https://github.com/roschaefer/git-splice/issues/208)) ([889c19e](https://github.com/roschaefer/git-splice/commit/889c19e0ae57258d7b9553bc50dcdd85f384e783))

## [0.10.0](https://github.com/roschaefer/git-splice/compare/v0.9.0...v0.10.0) (2026-10-22)


### Features

* **check-drawing:** draw a splice's upstreams side by side ([#219](https://github.com/roschaefer/git-splice/issues/219)) ([14a647a](https://github.com/roschaefer/git-splice/commit/14a647adac852120b4b882d24b40d7cdf7432a87))
* **merge:** pull an upstream branch rebased since the synced commit, from its fork point ([#207](https://github.com/roschaefer/git-splice/issues/207)) ([cadf751](https://github.com/roschaefer/git-splice/commit/cadf751380e0f4e4254e00807895f459cb358b0b))

## [0.9.0](https://github.com/roschaefer/git-splice/compare/v0.8.4...v0.9.0) (2026-10-18)


### Features

* **scrut:** run docs-check's documents in parallel with scrut --jobs ([#189](https://github.com/roschaefer/git-splice/issues/189)) ([283e8b6](https://github.com/roschaefer/git-splice/commit/283e8b6d412d9dc30a5a67a7c9c8118fe740e928))

## [0.8.4](https://github.com/roschaefer/git-splice/compare/v0.8.3...v0.8.4) (2026-10-16)


### Performance Improvements

* **order:** order splices without a subshell per path ([#184](https://github.com/roschaefer/git-splice/issues/184)) ([72c532f](https://github.com/roschaefer/git-splice/commit/72c532ffbfda0ab0a1d599112cb55903bb58705f))
* **status:** ask git status once for all splices ([#191](https://github.com/roschaefer/git-splice/issues/191)) ([cc6b002](https://github.com/roschaefer/git-splice/commit/cc6b0026f4c627459433b8284f6b10ec94d9afb6))

## [0.8.3](https://github.com/roschaefer/git-splice/compare/v0.8.2...v0.8.3) (2026-10-16)


### Bug Fixes

* **rebuild:** make the rebuild independent of i18n.commitEncoding ([#185](https://github.com/roschaefer/git-splice/issues/185)) ([d6b7f5a](https://github.com/roschaefer/git-splice/commit/d6b7f5adc303f0765bade1aaff07d4e9de2cd5a4)), closes [#179](https://github.com/roschaefer/git-splice/issues/179)
* **rebuild:** refuse when a shallow clone cuts off where the rebuild starts ([#177](https://github.com/roschaefer/git-splice/issues/177)) ([f0489b3](https://github.com/roschaefer/git-splice/commit/f0489b3b5b59017f1784e8e458df89cae1cf4425)), closes [#117](https://github.com/roschaefer/git-splice/issues/117)

## [0.8.2](https://github.com/roschaefer/git-splice/compare/v0.8.1...v0.8.2) (2026-10-15)


### Bug Fixes

* **pull:** fetch the synced commit a pull above moves a splice to ([#127](https://github.com/roschaefer/git-splice/issues/127)) ([dd99dc6](https://github.com/roschaefer/git-splice/commit/dd99dc6a45011b31e4b4241cc236f5eb41bbf1bd))

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
