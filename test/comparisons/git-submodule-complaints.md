# Complaints about Git submodules

Why projects leave submodules, from threads on GitHub and a few
mailing lists. Collected 2026-10-16 with GitHub search (REST for issues
and PRs, GraphQL for Discussions) and web search. Every entry was opened
and checked; the quote or summary comes from the thread itself. In the
Size column, `12c` means 12 comments.

GitHub's Discussions search is noisy: most hits for "submodule" are
how-to questions. Complaint threads mostly live in issues and PRs.

## Recurring themes

1. Not cloned by default; forgetting `--recursive` / `submodule update` ([scala-native](https://github.com/scala-native/scala-native/issues/61), [Elemental](https://github.com/elemental/Elemental/issues/52)).
2. GitHub source archives lack submodules ([julia](https://github.com/JuliaLang/julia/issues/5441), [Yaafe](https://github.com/Yaafe/Yaafe/issues/41), [community#6003](https://github.com/orgs/community/discussions/6003)).
3. Pointer churn: accidental reverts, merge conflicts on the gitlink, forgotten bumps ([TypeScript](https://github.com/microsoft/TypeScript/pull/33425), [certbot](https://github.com/certbot/website/issues/682), [julia](https://github.com/JuliaLang/julia/issues/5441)).
4. Developing inside a submodule: detached HEAD, pull resets to the pinned commit ([OpenROAD](https://github.com/The-OpenROAD-Project/OpenROAD/discussions/683), [opencast](https://github.com/orgs/opencast/discussions/7277)).
5. Size and install time of recursive submodules ([hhvm](https://github.com/facebook/hhvm/pull/8738), [mmtf-cpp](https://github.com/rcsb/mmtf-cpp/issues/21), [sablier](https://github.com/sablier-labs/evm-monorepo/discussions/508)).
6. Repos that aren't really independent ([FilOzone](https://github.com/FilOzone/filecoin-services/issues/229), [korlibs](https://github.com/korlibs/korlibs/discussions/189)). These are the closest to what `git-splice` targets.

## GitHub Discussions

| Thread | Year | Size | Complaint |
|---|---|---|---|
| [E3SM-Project/E3SM#8221](https://github.com/E3SM-Project/E3SM/discussions/8221) — Submodules vs FetchContent | 2026 | 9c | Climate model team can't agree; lists pros/cons of submodules for users vs developers. Spun off PR [#8214](https://github.com/E3SM-Project/E3SM/pull/8214), which replaced the mam4xx submodules with FetchContent. |
| [opencast/opencast#7277](https://github.com/orgs/opencast/discussions/7277) — Replacing admin/editor releases with git submodules | 2025 | 6c | Goes *towards* submodules, but the team asks for a documentation page of "submodule woes" with a fix for every common scenario (e.g. changing branches). Follow-ups: [#7576](https://github.com/orgs/opencast/discussions/7576) (HTTPS vs SSH URLs), [#7592](https://github.com/orgs/opencast/discussions/7592). |
| [sablier-labs/evm-monorepo#508](https://github.com/sablier-labs/evm-monorepo/discussions/508) — Installing dependencies with pnpm instead of git submodules | 2023 | 4c | "Using git submodules has started to be a pain in the ass because of the installation times." Recursive submodules complicate remappings. |
| [The-OpenROAD-Project/OpenROAD#683](https://github.com/The-OpenROAD-Project/OpenROAD/discussions/683) — What's the workflow of developing in submodules? | 2021 | 5c | Contributor commits inside a submodule, forks the parent only, and `git pull --recurse-submodules` keeps checking out the old pinned commit. Classic detached-HEAD confusion. |
| [korlibs/korlibs#189](https://github.com/korlibs/korlibs/discussions/189) — Migrate korlibs submodules into a single Gradle mono repo | 2026 | 6c | Proposal to merge `korlibs-*` submodule repos into one monorepo to make maintenance and releases easier. |
| [usnistgov/blossom-member#17](https://github.com/usnistgov/blossom-member/discussions/17) — Reorganizing blossom repos and submodules | 2025 | 3c | Several submodules are out of date; restructuring discussion. |
| [kiali/kiali#4587](https://github.com/kiali/kiali/discussions/4587) — Join kiali backend and frontend repos | 2022 | 5c | Monorepo vs separate repos; submodules suggested as a trial. |
| [zephyrproject-rtos/zephyr#34713](https://github.com/zephyrproject-rtos/zephyr/discussions/34713) — CI with multiple git repos (west or similar) | 2021 | 3c | How to do CI across multiple repos; linked from SOF's "drop submodules" issue below. |
| [community/community#62322](https://github.com/orgs/community/discussions/62322) — Transitioning to GitHub | 2023 | 1c | Answer: "If starting fresh with git, I wouldn't really recommend submodules … can overly complicate things quite quickly." |
| [community/community#6003](https://github.com/orgs/community/discussions/6003) — No way to disable auto-generated source code zip links | 2021 | 43c, 147 up | Five posts mention submodules: GitHub's source archives lack submodule contents and can't be turned off. |

## Issues and PRs: "get rid of submodules"

| Thread | Year | Size | Complaint |
|---|---|---|---|
| [rust-lang/rust#70651](https://github.com/rust-lang/rust/issues/70651) — Replace submodules with subtrees | 2020 | 54c | Clippy moved to a subtree; "we are basically in a monorepo state, so you just edit stuff in `src/tools/clippy/`". Prominent precedent for subtrees. |
| [JuliaLang/julia#5441](https://github.com/JuliaLang/julia/issues/5441) — get rid of deps submodules | 2014 | 12c | "They're a PITA. They're often accidentally reverted. Can't build from tarball without git. They aren't mirrored." |
| [JuliaLang/julia#10743](https://github.com/JuliaLang/julia/pull/10743) — remove git submodules | 2015 | 37c | Follow-up PR: build without git from a zip/tarball. |
| [microsoft/TypeScript#33425](https://github.com/microsoft/TypeScript/pull/33425) — Remove all submodules | 2019 | 5c | "I give up - submodules are broken and a failed experiment. `ignore = all` isn't respected … continuously having stupid diffs and 'merge conflicts' in the submodule references." |
| [certbot/website#682](https://github.com/certbot/website/issues/682) — Stop using submodules | 2020 | 3c | "git submodules are awful. On top of that, we regularly forget to update the submodule." |
| [FilOzone/filecoin-services#229](https://github.com/FilOzone/filecoin-services/issues/229) — Proposal: monorepo & no git submodules | 2025 | 17c | "challenges with versioning and keeping everything in sync, and submodules just plain suck. We're pretending that these contracts are independent, but they're not." |
| [scala-native/scala-native#61](https://github.com/scala-native/scala-native/issues/61) — Move away from git submodules | 2016 | 7c | "Git submodules are extremely confusing as they don't get cloned by default." |
| [elemental/Elemental#52](https://github.com/elemental/Elemental/issues/52) — Moving away from git submodules | 2015 | 9c | GitHub zip/tarballs lack submodules, so downloads fail to build in confusing ways; "git submodules confuse users". |
| [AppImageCommunity/appimaged#80](https://github.com/AppImageCommunity/appimaged/issues/80) — Get rid of git submodules if they cannot be managed by the GitHub web interface | 2019 | 13c | Can't update or check a submodule from the GitHub web UI. |
| [caracal-pipeline/caracal#200](https://github.com/caracal-pipeline/caracal/issues/200) — Stop using submodules | 2018 | 7c | "Easy to get something up and running quickly, but difficult to work around when releasing and packaging software." |
| [google/mozc#1320](https://github.com/google/mozc/issues/1320) — Stop using git submodules | 2025 | 1c | History: gclient/DEPS (2010) → submodules (2015) → leaving submodules; managing C++ deps "has always been a challenge". |
| [thesofproject/sof#3517](https://github.com/thesofproject/sof/issues/3517) — drop git submodules and switch to Zephyr's "west" | 2020 | 12c | Rationale in a linked doc; multi-repo tool instead of submodules. |
| [es-ude/elastic-ai.runtime.enV5#132](https://github.com/es-ude/elastic-ai.runtime.enV5/issues/132) — Stop using git submodules for third-party deps | 2023 | 2c | Pro/con list: "complicated to use and setup, can confuse IDEs, easy to accidentally pick…" wrong commits. |
| [rcsb/mmtf-cpp#21](https://github.com/rcsb/mmtf-cpp/issues/21) — release without submodules | 2018 | 4c | Projects embedding mmtf-cpp as a submodule don't want its large recursive submodules. |
| [Yaafe/Yaafe#41](https://github.com/Yaafe/Yaafe/issues/41) — Getting rid of git submodules to ease migration to conda-forge | 2017 | 2c | conda-forge wants source archives; GitHub's lack submodules. |
| [dapphub/dapptools#377](https://github.com/dapphub/dapptools/pull/377) — Remove submodules and simplify installation | 2020 | 27c | Install script "kind of magical" with a support burden; switch to Nix. |
| [input-leap/input-leap#1984](https://github.com/input-leap/input-leap/issues/1984) — Remove submodules | 2024 | 17c | Replace every submodule with system/CMake dependencies. |
| [helix-editor/helix#1659](https://github.com/helix-editor/helix/pull/1659) — replace submodules with flags for fetching and building grammars | 2022 | 15c | Tree-sitter grammars as submodules replaced by `hx --grammar fetch/build`. |
| [facebook/hhvm#8738](https://github.com/facebook/hhvm/pull/8738) — Stop using submodules for fb-mysql and zstd | 2020 | 7c | Submodule > 550 MB vs tarball < 150 MB, and downloaded even when unneeded. |
| [NuGet/NuGet.Client#4536](https://github.com/NuGet/NuGet.Client/pull/4536) — Stop using FileSystem and Common submodules | 2022 | 12c | Inlines two submodules. |
| [cue-lang/cue#1989](https://github.com/cue-lang/cue/issues/1989) — cuelang.org: Move away from git submodules | 2021 | 1c | Nested submodules (docsy → bootstrap, font-awesome) for local dev and Netlify. |
| [docsy/docsy#889](https://github.com/docsy/docsy/pull/889) — Drop Bootstrap and Font Awesome git submodules | 2022 | 6c | The upstream side of the cue complaint: docsy dropped its submodules. |
| [ome/omero-guides#23](https://github.com/ome/omero-guides/pull/23) — Remove submodules | 2020 | 31c | Submodules broke search on readthedocs; replaced with sub-projects. |
| [google/brunsli#121](https://github.com/google/brunsli/pull/121) — Get rid of git submodules | 2021 | 4c | No description. |
| [NixOS/nixpkgs#239291](https://github.com/NixOS/nixpkgs/pull/239291) — python3Packages.torch: drop submodules in favor of Nixpkgs | 2023 | 4c | Packagers replace PyTorch's vendored submodules with system packages. |
| [mattermost/mattermost-plugins#19](https://github.com/mattermost/mattermost-plugins/pull/19) — Replace plugin submodules with a list of links | 2019 | 4c | Plugin index as submodules replaced by links. |
| [sourcegraph#33574](https://github.com/sourcegraph/sourcegraph-public-snapshot/pull/33574) — Remove git submodules for tree-sitter grammars | 2022 | 1c | Removes a ~100-line build.rs as well. |
| [base/base#575](https://github.com/base/base/pull/575) — remove git submodules and switch to forge soldeer | 2026 | 4c | Solidity/Foundry projects leaving submodules for a package manager. |

## Related debates (not purely complaints)

| Thread | Year | Notes |
|---|---|---|
| [ggml-org/whisper.cpp#613](https://github.com/ggml-org/whisper.cpp/pull/613) — Added ggml as submodule | 2023 | 12c. Defends submodules (forces looking at downstream API impact); subtree and git-subrepo suggested as alternatives. |
| [ohmyzsh/ohmyzsh#377](https://github.com/ohmyzsh/ohmyzsh/issues/377) — Proposal to Simplify OH-MY-ZSH | 2011 | 87c. Plugin layout debate where "submodule hell" comes up. |
| [Carthage/Carthage#135](https://github.com/Carthage/Carthage/issues/135) | — | 57c. `carthage update` fails when a submodule listed in `.gitmodules` doesn't exist. |

## Outside GitHub

- [SWI-Prolog Discourse](https://swi-prolog.discourse.group/t/improving-contributor-guide-discoverability-was-consolidating-the-71-github-repositories-to-simplify-maintenance-and-contribution/492): consolidating 71 submodule repos with git-subtree to ease contribution.
- [web-platform-tests (W3C list, 2017)](https://lists.w3.org/Archives/Public/public-test-infra/2017AprJun/0016.html): removing all "essential" submodules — "no one loves submodules".
- [Git mailing list: why no `git submodule rm`](https://public-inbox.org/git/xmqqbl3ihu6l.fsf@gitster.g/): Junio on the unhappy paths of removal.
- [OpenMC Discourse: tarball missing submodule source](https://openmc.discourse.group/t/openmc-v0-12-0-tarball-missing-submodule-source/707).

