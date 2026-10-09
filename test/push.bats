setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  local scenario
  for scenario in \
    up-to-date \
    up-to-date/push-ahead \
    up-to-date/pull-ahead \
    up-to-date/push-ahead/diverged-common-ancestor \
    up-to-date/push-ahead/diverged-unrelated-history \
    never-fetched \
    up-to-date/feature-branch-unchanged \
    up-to-date/feature-branch-unchanged/feature-branch-changed \
    up-to-date/diverged-then-pulled \
    up-to-date/push-ahead/pushed-then-pulled/pushed-then-changed \
    up-to-date/shared-remote-url \
    default-branch \
    up-to-date/push-ahead/uncommitted-changes; do
    load "scenarios/$scenario/setup"
  done
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "push: publishes the rebuilt commits and updates the private ref" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a)"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: pushed ${rebuilt:0:7} to main"* ]]
  [ "$(git -C "$upstream" rev-parse main)" = "$rebuilt" ]
  [ "$(git rev-parse "$(upstream_refs "$upstream")main")" = "$rebuilt" ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "local change" ]
  ! git -C "$upstream" cat-file -e main:.splice 2>/dev/null
}

@test "push: writes nothing to the monorepo and creates no Git remote" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -z "$(git status --porcelain)" ]
  [ -z "$(git remote)" ]
}

@test "push: a plain git push has nowhere to send the monorepo" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config push.autoSetupRemote true
  git checkout -q -b topic
  run git push
  [ "$status" -ne 0 ]
  ! git -C "$upstream" rev-parse --verify --quiet topic
}

@test "push: then pushing again has nothing to do" {
  scenario_pushed_then_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  run cmd_push vendor/a
  [[ "$output" == *"vendor/a: nothing to push"* ]]
}

@test "push: after pulling a divergence, sends the local commit and a merge" {
  scenario_diverged_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" rev-list --count --merges main)" -eq 1 ]
  git -C "$upstream" log --format=%s main | grep -qx "local change"
}

@test "push: refuses when upstream has commits this branch lacks" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"run 'git splice pull vendor/a' first"* ]]
}

@test "push: nothing to push when upstream is ahead" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"upstream is ahead"* ]]
}

@test "push: --force discards commits only upstream has" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push --force vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "seed" ]
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = up-to-date ]
}

@test "push: --force works after upstream lost the synced commit" {
  scenario_push_ahead "$monorepo" "$upstream"
  # Upstream is rebuilt from scratch, so the synced commit is gone for good,
  # as in a fresh clone of the monorepo.
  rm -rf "$upstream"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "brand new unrelated history"
  cd "$monorepo"
  git for-each-ref --format='delete %(refname)' refs/splices/ | git update-ref --stdin
  git reflog expire --expire=now --all && git gc -q --prune=now
  fetch_splice "$monorepo" "$upstream" vendor/a
  ! git cat-file -e "$(splice_config vendor/a commit)^{commit}" 2>/dev/null
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = unrelated-history ]
  run cmd_push --force vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "local change" ]
}

@test "push: refuses unrelated history, --force overwrites it" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"pick a side"* ]]
  run cmd_push --force vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "local change" ]
}

@test "push: asks for a fetch first" {
  scenario_never_fetched "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"not fetched"* ]]
}

@test "push: creates a missing upstream branch only if the splice changed" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [[ "$output" == *"nothing to push (upstream has no 'feature' branch; unchanged since 'main')"* ]]
  ! git -C "$upstream" rev-parse --verify --quiet feature
  commit_local "$monorepo" "vendor/a" "local change"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"this push creates it (changed since 'main')"* ]]
  [ "$(git -C "$upstream" log -1 --format=%s feature)" = "local change" ]
  [ "$(git -C "$upstream" rev-parse feature^)" = "$(git -C "$upstream" rev-parse main)" ]
}

@test "push: asks for --base when the base branch can't be found" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  git config --unset init.defaultBranch
  run cmd_push vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"re-run with --base <branch>"* ]]
  run cmd_push --base main vendor/a
  [ "$status" -eq 0 ]
}

@test "push: removes its SSH control folder and exits cleanly" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir "$BATS_TEST_TMPDIR/tmp"
  TMPDIR="$BATS_TEST_TMPDIR/tmp" run splice push vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: pushed $(git rev-parse --short=7 "$(upstream_refs "$upstream")main") to main" ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/tmp")" ]
}

@test "push: on the default branch, pushes to upstream's default branch" {
  scenario_default_branch "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"to master"* ]]
  [ "$(git -C "$upstream" log -1 --format=%s master)" = "local change" ]
  ! git -C "$upstream" rev-parse --verify --quiet main
}

@test "push: needs paths or --all, and pushes every changed splice with --all" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push
  [ "$status" -eq 1 ]
  commit_local "$monorepo" "vendor/b" "change in b"
  run cmd_push --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: nothing to push"* ]]
  [[ "$output" == *"vendor/b: pushed"* ]]
}

@test "push: warns about uncommitted changes and pushes only committed ones" {
  scenario_uncommitted_changes "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "??   vendor/a: uncommitted changes aren't pushed -- commit them first" ]]
  [[ "$output" == *"vendor/a: pushed"* ]]
  [ "$(git -C "$upstream" show main:file.txt)" = "$(git show HEAD:vendor/a/file.txt)" ]
}

@test "push: says so when it can't check for uncommitted changes" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  # An invalid value that only git status reads makes it fail.
  git config status.relativePaths bogus
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "??   vendor/a: could not check for uncommitted changes (git status failed) -- only committed ones are pushed" ]]
  [[ "$output" == *"vendor/a: pushed"* ]]
}

# Prints the rebuild of vendor/a with its last commit's message replaced
# by <message>, as an edit in a separate worktree would make it.
reworded_rebuild() {
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a)"
  git commit-tree --no-gpg-sign "$rebuilt^{tree}" -p "$rebuilt^" -m "$1"
}

@test "push --rebuild: pushes the given commit instead of the rebuild, e.g. with a reworded message" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local edited
  edited="$(reworded_rebuild "fix the parser")"
  run cmd_push --rebuild "$edited" vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: pushed ${edited:0:7} to main" ]
  [ "$(git -C "$upstream" rev-parse main)" = "$edited" ]
  [ "$(git rev-parse "$(upstream_refs "$upstream")main")" = "$edited" ]
}

@test "push --rebuild: creates a missing upstream branch with the given commit" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local edited
  edited="$(reworded_rebuild "fix the parser")"
  run cmd_push --rebuild="$edited" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" rev-parse feature)" = "$edited" ]
}

@test "push --rebuild: refuses a commit with other files than the folder, which only a monorepo commit may change" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt other
  rebuilt="$(rebuild_splice vendor/a)"
  other="$(git commit-tree --no-gpg-sign "$(git rev-parse "$rebuilt^^{tree}")" -p "$rebuilt" -m "undo")"
  run cmd_push --rebuild "$other" vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a: ${other:0:7} has other files than the folder -- --rebuild only takes edits to the history; commit changes to files in the monorepo" ]
  [ "$(git -C "$upstream" rev-parse main)" = "$(splice_config vendor/a commit)" ]
}

@test "push --rebuild: refuses a commit that doesn't contain the synced commit, even where the upstream would take it" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local root synced
  root="$(git commit-tree --no-gpg-sign "$(rebuild_splice vendor/a)^{tree}" -m "squashed")"
  synced="$(splice_config vendor/a commit)"
  run cmd_push --rebuild "$root" vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a: ${root:0:7} doesn't contain the synced commit ${synced:0:7} -- edit only the commits after it" ]
  ! git -C "$upstream" rev-parse --verify --quiet feature
}

@test "push --rebuild: takes a commit and exactly one splice" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push --rebuild nope vendor/a
  [ "$output" = "!!   --rebuild: not a commit: nope" ]
  run cmd_push --rebuild HEAD vendor/a vendor/b
  [ "$output" = "!!   --rebuild takes exactly one splice" ]
  run cmd_push --rebuild HEAD --all
  [ "$output" = "!!   --rebuild takes exactly one splice" ]
  run cmd_push vendor/a --rebuild
  [ "$output" = "!!   --rebuild needs a commit" ]
  run cmd_status --rebuild HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   unknown option: --rebuild" ]]
}
