setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  local scenario
  for scenario in up-to-date push-ahead pull-ahead diverged-common-ancestor \
    diverged-unrelated-history never-fetched feature-branch-unchanged \
    feature-branch-changed diverged-then-pulled pushed-then-changed \
    shared-remote-url default-branch; do
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
  [ "$(git rev-parse refs/splices/vendor/a/main)" = "$rebuilt" ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "local change" ]
  ! git -C "$upstream" cat-file -e main:.splice 2>/dev/null
}

@test "push: writes nothing to the monorepo and creates no Git remote" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  cmd_push vendor/a
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
  cmd_push vendor/a
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
  [ "$output" = "ok   vendor/a: pushed $(git rev-parse --short=7 refs/splices/vendor/a/main) to main" ]
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
