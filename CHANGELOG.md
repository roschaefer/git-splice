# Changelog

## 0.1.0 (2026-09-28)


### Features

* **ci:** add rolling edge release on push to main ([#7](https://github.com/roschaefer/git-subtrees/issues/7)) ([51cd2c6](https://github.com/roschaefer/git-subtrees/commit/51cd2c6d23f03dccece9e9e96680041edcb1a70d))
* **cli:** add --version, cut releases with release-please ([#34](https://github.com/roschaefer/git-subtrees/issues/34)) ([b7ccaa7](https://github.com/roschaefer/git-subtrees/commit/b7ccaa77338dedeb665489bd105a168131f80958))
* **completions:** add bash, zsh, and fish shell completions ([eabc6b3](https://github.com/roschaefer/git-subtrees/commit/eabc6b37f1398e124637cb319da3723ddefbe2a5))
* **diff:** show changes before pushing subtrees ([#16](https://github.com/roschaefer/git-subtrees/issues/16)) ([755c7d8](https://github.com/roschaefer/git-subtrees/commit/755c7d8cf043d1e27b4f1d890d92d1d5c85c47f7))
* **init:** add the remote's base branch when it lacks the current one ([#21](https://github.com/roschaefer/git-subtrees/issues/21)) ([3df2b44](https://github.com/roschaefer/git-subtrees/commit/3df2b44c00d8620c0f8e65003f11d24479484a95))
* **merge:** add `git subtrees merge`, make `pull` fetch + merge ([#18](https://github.com/roschaefer/git-subtrees/issues/18)) ([0b402bf](https://github.com/roschaefer/git-subtrees/commit/0b402bf734856cc3641171e74a4b546b8dcb4f86))
* **nix:** package git-subtrees in the flake ([#35](https://github.com/roschaefer/git-subtrees/issues/35)) ([36a1aa4](https://github.com/roschaefer/git-subtrees/commit/36a1aa4203a1a29d99411dd4c2c75622d724ea5e))
* **playground:** add simulate-remote-change to trigger pull scenarios on demand ([b0d6836](https://github.com/roschaefer/git-subtrees/commit/b0d683687fd73d32c126850483412f4c3f3e981b))
* **playground:** drop into a shell inside the sandbox automatically ([2aa3201](https://github.com/roschaefer/git-subtrees/commit/2aa3201f632ced31494c6cca89b5dee8326b2886))
* **push:** create a missing remote branch only if the subtree changed on this branch ([#10](https://github.com/roschaefer/git-subtrees/issues/10)) ([25f86e6](https://github.com/roschaefer/git-subtrees/commit/25f86e6345bcb6f487c9697ce5c9f40173ef10c1))
* **subtrees:** ground-up rewrite with tests, lint, and CI ([53a9394](https://github.com/roschaefer/git-subtrees/commit/53a939457dcdf73f3e0ff8b99f6084dbaceac465))


### Bug Fixes

* **cli:** terminate options before remote-name arguments ([#6](https://github.com/roschaefer/git-subtrees/issues/6)) ([e058c05](https://github.com/roschaefer/git-subtrees/commit/e058c050d34f01cc91f525b1e25ca943309c04bf))
* **completions:** never run branch names in bash, complete --base=&lt;value&gt; ([#25](https://github.com/roschaefer/git-subtrees/issues/25)) ([9b30db8](https://github.com/roschaefer/git-subtrees/commit/9b30db858a1fa07731f3c7757554d6bced78e847))
* **diff:** report a failed pager even when SIGPIPE is ignored ([#22](https://github.com/roschaefer/git-subtrees/issues/22)) ([ba4e21f](https://github.com/roschaefer/git-subtrees/commit/ba4e21fd747e21f1a25b2d4432ee1c01ddb68793))
* **discover:** refuse nested subtrees, restructure the README ([#19](https://github.com/roschaefer/git-subtrees/issues/19)) ([d052505](https://github.com/roschaefer/git-subtrees/commit/d0525058f6debcad539a5cbc644de2b565be5e96))
* **init:** record a sync point for a folder copied in by hand ([#26](https://github.com/roschaefer/git-subtrees/issues/26)) ([b0a9434](https://github.com/roschaefer/git-subtrees/commit/b0a943499269867f669950ec313651ac9aa4f063))
* **push:** address review follow-ups on --base handling and the walkthrough ([#12](https://github.com/roschaefer/git-subtrees/issues/12)) ([30f270e](https://github.com/roschaefer/git-subtrees/commit/30f270ea9a02817b9db2e721d961cc5dad2d9b70))
* run every command from the repo root ([#5](https://github.com/roschaefer/git-subtrees/issues/5)) ([0f0edfa](https://github.com/roschaefer/git-subtrees/commit/0f0edfafc29e053b042c7ac0fee9daddf0262a7b))
* **status:** decide who is ahead by splitting HEAD ([#29](https://github.com/roschaefer/git-subtrees/issues/29)) ([0baf7ff](https://github.com/roschaefer/git-subtrees/commit/0baf7ff138378f953b0a26ac8b2a9da08fe60248))
* **status:** prevent subtree output truncation ([#2](https://github.com/roschaefer/git-subtrees/issues/2)) ([c43e0d0](https://github.com/roschaefer/git-subtrees/commit/c43e0d0be233a4176136ce248110de5c8be6fe51))
* **status:** push local changes that predate a pull of a divergence ([#20](https://github.com/roschaefer/git-subtrees/issues/20)) ([696f4c4](https://github.com/roschaefer/git-subtrees/commit/696f4c4aa3208f9cbd1179d2d4f28f2c8a0f9fd5))
* **tests:** make subtree fixtures branch-stable ([e20cfe8](https://github.com/roschaefer/git-subtrees/commit/e20cfe86f011936201f3df574f61693bfc02f88e))


### Performance Improvements

* **bench:** time commands on a synthetic monorepo, per PR in CI ([#32](https://github.com/roschaefer/git-subtrees/issues/32)) ([5fc1631](https://github.com/roschaefer/git-subtrees/commit/5fc163159d4fbc046f611aba2bb88c90db7ff7fe))
* **pull:** fetch subtrees in parallel ([#3](https://github.com/roschaefer/git-subtrees/issues/3)) ([17c0009](https://github.com/roschaefer/git-subtrees/commit/17c00094e722da7eb0fca0dd696f922387e12c4c))
