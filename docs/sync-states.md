# Sync states

`status` reports one of these states for each splice, and `merge`, `pull`
and `push` act on it. Each example is a small, tested scenario;
[all scenarios](../test/scenarios/README.md) cover more situations.

| State | Meaning | What to do |
| --- | --- | --- |
| never fetched | The upstream wasn't fetched in this clone yet. ([example](../test/scenarios/never-fetched/README.md)) | Run `git splice fetch`. |
| up to date | Both sides are the same. ([example](../test/scenarios/up-to-date/README.md)) | Nothing to do. |
| push | Only your side changed. ([example](../test/scenarios/up-to-date/push-ahead/README.md)) | Run `git splice push`. |
| pull | Only the upstream changed. ([example](../test/scenarios/up-to-date/pull-ahead/README.md)) | Run `git splice pull`. |
| diverged | Both sides changed since they last matched. ([example](../test/scenarios/up-to-date/push-ahead/diverged-common-ancestor/README.md)) | Run `git splice pull`, then `push`. On a conflict, resolve it and `git commit` first. |
| unrelated history | Both sides changed and share no history, e.g. the upstream was rebuilt from scratch. ([example](../test/scenarios/up-to-date/push-ahead/diverged-unrelated-history/README.md)) | Pick a side. `merge`, `pull` and `push` refuse to guess and print the commands to keep either side, or both. |
| upstream has no such branch | The upstream has no branch with your branch's name. ([unchanged](../test/scenarios/up-to-date/feature-branch-unchanged/README.md), [changed](../test/scenarios/up-to-date/feature-branch-unchanged/feature-branch-changed/README.md)) | Run `git splice push`. It creates the branch only if the splice changed. |
