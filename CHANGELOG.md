# Changelog

## [0.21.0](https://github.com/roschaefer/git-splice/compare/v0.20.0...v0.21.0) (2026-11-09)


### Features

* **check-drawing:** a drawing with lanes has one for every splice ([#442](https://github.com/roschaefer/git-splice/issues/442)) ([584c3b8](https://github.com/roschaefer/git-splice/commit/584c3b803ae710740686e0ee4e3e2ac859df335c))
* **check-drawing:** splice trees, written from the repository ([#440](https://github.com/roschaefer/git-splice/issues/440)) ([8eb07e5](https://github.com/roschaefer/git-splice/commit/8eb07e56b8cda049ae79d83af5b80e02b9c15241))
* make the message of the commits git-splice writes from a template with --message-template ([#422](https://github.com/roschaefer/git-splice/issues/422)) ([1442a19](https://github.com/roschaefer/git-splice/commit/1442a1957d0935ba668a11bbfdbed4f965f6f3e0))
* **pull:** --recursive pulls a splice and every splice below it, as one commit ([#451](https://github.com/roschaefer/git-splice/issues/451)) ([c418501](https://github.com/roschaefer/git-splice/commit/c418501228b374320b2c9b54479395577a882699))


### Bug Fixes

* **pull:** refuse a splice and one inside it, whose pull decides what's there ([#454](https://github.com/roschaefer/git-splice/issues/454)) ([961cad2](https://github.com/roschaefer/git-splice/commit/961cad26081c08a91f413147c84411d40af80b1b))
* **rebuild:** a nested splice's own new synced commit wins over the upstream above ([#430](https://github.com/roschaefer/git-splice/issues/430)) ([e2daebc](https://github.com/roschaefer/git-splice/commit/e2daebc9a38f2414d19ece4c50238aee7c6734a8)), closes [#428](https://github.com/roschaefer/git-splice/issues/428)

## [0.20.0](https://github.com/roschaefer/git-splice/compare/v0.19.0...v0.20.0) (2026-11-07)


### Features

* **check-drawing:** check that each commit the prose names is shown on its page ([#398](https://github.com/roschaefer/git-splice/issues/398)) ([640b5ef](https://github.com/roschaefer/git-splice/commit/640b5efefef901c028862835d9dccbe9d80e2575)), closes [#394](https://github.com/roschaefer/git-splice/issues/394)
* **check-drawing:** check that each drawing appears next to its check ([#399](https://github.com/roschaefer/git-splice/issues/399)) ([c8d0a29](https://github.com/roschaefer/git-splice/commit/c8d0a294bc7475d958fe525eb3618ad6f34080e9)), closes [#395](https://github.com/roschaefer/git-splice/issues/395)
* **check-drawing:** draw a commit a committed file names as a dashed arrow ([#411](https://github.com/roschaefer/git-splice/issues/411)) ([b416eb9](https://github.com/roschaefer/git-splice/commit/b416eb9ff7d0ea43279ef1c17a99444c85db9474))
* **check-drawing:** explain dashes and primes once, in a central legend ([#402](https://github.com/roschaefer/git-splice/issues/402)) ([b3bffdd](https://github.com/roschaefer/git-splice/commit/b3bffdde0b58546d47e69755105ae471d1b8e8ab))
* **check-drawing:** outline blue every pull a drawing shows, at any level ([#401](https://github.com/roschaefer/git-splice/issues/401)) ([d18ab04](https://github.com/roschaefer/git-splice/commit/d18ab04ea77ef12f16b5b175f733e8c95eddceee))
* **website:** count page views with GoatCounter ([#413](https://github.com/roschaefer/git-splice/issues/413)) ([963a400](https://github.com/roschaefer/git-splice/commit/963a400f0ac2e0a5f554b27696338a75a8028d79))


### Bug Fixes

* hash the empty tree from empty input instead of /dev/null ([#414](https://github.com/roschaefer/git-splice/issues/414)) ([cbb82dc](https://github.com/roschaefer/git-splice/commit/cbb82dcda053e734a10dc8a2bb076549c07c7faa))
* **pager:** page on Unix only, and detect a terminal the portable way ([#423](https://github.com/roschaefer/git-splice/issues/423)) ([966405e](https://github.com/roschaefer/git-splice/commit/966405ee9aacc92e24d7e7bc67dc241bb54e4e95))
* **pull:** say what a fresh clone hasn't fetched, not that the upstream lacks it ([#365](https://github.com/roschaefer/git-splice/issues/365)) ([022f615](https://github.com/roschaefer/git-splice/commit/022f615d94e458cf87c78afdf19d7c40963a70d3))
* **push:** leave the user's SSH setup alone, as git push does ([#412](https://github.com/roschaefer/git-splice/issues/412)) ([54da867](https://github.com/roschaefer/git-splice/commit/54da86738e7557bbd94e75f8173ff2493d2a3b9e))
* refuse a monorepo path or commit identity that isn't valid UTF-8 ([#416](https://github.com/roschaefer/git-splice/issues/416)) ([32983e2](https://github.com/roschaefer/git-splice/commit/32983e26cfae826a15f3bb525af29b52307ab779))
* run git without sh for merged output, and read exit codes off Unix too ([#417](https://github.com/roschaefer/git-splice/issues/417)) ([e2d1ea7](https://github.com/roschaefer/git-splice/commit/e2d1ea7dec16b531684a8075e77584878444f1f4))

## [0.19.0](https://github.com/roschaefer/git-splice/compare/v0.18.0...v0.19.0) (2026-11-05)


### Features

* **merge:** merge a commit made on top of the rebuild with --rebuilt-commit ([#362](https://github.com/roschaefer/git-splice/issues/362)) ([4644e7e](https://github.com/roschaefer/git-splice/commit/4644e7e29e54a72f1281fce76730fe6b731ab593))


### Bug Fixes

* **check-drawing:** judge a lane inside another by its whole shape ([#391](https://github.com/roschaefer/git-splice/issues/391)) ([c4e3398](https://github.com/roschaefer/git-splice/commit/c4e3398e970adaf1a7a95b4831af0bbd95810710))
* **init:** keep the default branch of the splices inside a new splice ([#361](https://github.com/roschaefer/git-splice/issues/361)) ([14ea635](https://github.com/roschaefer/git-splice/commit/14ea635363e03bb0d6dc60166fb52f411c810f77))

## [0.18.0](https://github.com/roschaefer/git-splice/compare/v0.17.1...v0.18.0) (2026-11-05)


### Features

* **check-drawing:** draw a branch of the monorepo with a splice's commits as a dashed box ([#372](https://github.com/roschaefer/git-splice/issues/372)) ([8f493b3](https://github.com/roschaefer/git-splice/commit/8f493b30935fee5dc74617557f39820491de8392))
* **docs:** add a help structure checker ([#357](https://github.com/roschaefer/git-splice/issues/357)) ([75b4d39](https://github.com/roschaefer/git-splice/commit/75b4d3946558840a10bbd72c3d8500c18cdc5f98))


### Bug Fixes

* **check-help:** enforce executable fragment boundaries ([#369](https://github.com/roschaefer/git-splice/issues/369)) ([f2635f1](https://github.com/roschaefer/git-splice/commit/f2635f14deb5bcb07ab4042b0fc75fec92dd0997))

## [0.17.1](https://github.com/roschaefer/git-splice/compare/v0.17.0...v0.17.1) (2026-11-04)


### Bug Fixes

* **nested:** read the .splice below again after a merge above ([#354](https://github.com/roschaefer/git-splice/issues/354)) ([386b4b2](https://github.com/roschaefer/git-splice/commit/386b4b22159e0e240a1ee09dd96fffee91dd062d)), closes [#69](https://github.com/roschaefer/git-splice/issues/69) [#195](https://github.com/roschaefer/git-splice/issues/195)

## [0.17.0](https://github.com/roschaefer/git-splice/compare/v0.16.3...v0.17.0) (2026-11-02)


### ⚠ BREAKING CHANGES

* **nix:** the Nix package needs Git on `PATH`, at least 2.40.
* **port:** installing from a clone means `cargo install`, not a symlink.

### Features

* **check-drawing:** read lineage from a Rust tool ([#324](https://github.com/roschaefer/git-splice/issues/324)) ([dce40c3](https://github.com/roschaefer/git-splice/commit/dce40c35bf05bd5d36e2646097bef97625e42390))
* **port:** add a Rust entrypoint that hands commands to bash ([#318](https://github.com/roschaefer/git-splice/issues/318)) ([57a7e98](https://github.com/roschaefer/git-splice/commit/57a7e987c6add11d5b4bb942e15c307cfc39dd13))
* **port:** port clone, init and push to Rust ([#321](https://github.com/roschaefer/git-splice/issues/321)) ([669fc38](https://github.com/roschaefer/git-splice/commit/669fc382b74c9b955597f3a843fe7be81e5f8e08))
* **port:** port fetch, merge and pull to Rust ([#320](https://github.com/roschaefer/git-splice/issues/320)) ([a217245](https://github.com/roschaefer/git-splice/commit/a217245938e3afeba6aa7d275e2496d194591ff9))
* **port:** port status, diff, log, key, rebuild and boundary to Rust ([#319](https://github.com/roschaefer/git-splice/issues/319)) ([fd6a82b](https://github.com/roschaefer/git-splice/commit/fd6a82be9de4f457e41dd6b9080f7a6d5614b197))
* **port:** replace the bash implementation with the Rust one ([#322](https://github.com/roschaefer/git-splice/issues/322)) ([f721831](https://github.com/roschaefer/git-splice/commit/f721831611891bed9edbda4e570055de5d9b3889))
* **release:** attach binaries to releases ([#323](https://github.com/roschaefer/git-splice/issues/323)) ([c8c4117](https://github.com/roschaefer/git-splice/commit/c8c411788e42c36d07d7acf0c2e7e0ab4051467e))


### Bug Fixes

* **bench:** keep Git's background repack out of the fixture ([#329](https://github.com/roschaefer/git-splice/issues/329)) ([35e185a](https://github.com/roschaefer/git-splice/commit/35e185a21b31719ae14acfd0f4116e78ebf703d7))
* **diff:** exit 127 when the pager can't start ([#317](https://github.com/roschaefer/git-splice/issues/317)) ([75cda17](https://github.com/roschaefer/git-splice/commit/75cda17964b4b898cca82bd171710b56eee74b16))


### Build System

* **nix:** run the user's Git, and take the dev shell's from unstable ([#330](https://github.com/roschaefer/git-splice/issues/330)) ([dacd7a1](https://github.com/roschaefer/git-splice/commit/dacd7a17294357878e8954e739976eb25a832e76))

## [0.16.3](https://github.com/roschaefer/git-splice/compare/v0.16.2...v0.16.3) (2026-10-30)


### Bug Fixes

* **clone:** refuse where the monorepo's checkout attributes would apply to a splice ([#304](https://github.com/roschaefer/git-splice/issues/304)) ([161f020](https://github.com/roschaefer/git-splice/commit/161f0200705d6fe668154863bb8a607ad2818cdf))

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
