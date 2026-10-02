setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/up-to-date/setup'
  load 'scenarios/push-ahead/setup'
  load 'scenarios/pull-ahead/setup'
  load 'scenarios/feature-branch-unchanged/setup'
  load 'scenarios/feature-branch-changed/setup'
  load 'scenarios/shared-remote-url/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "diff: shows the patch that would be pushed, with upstream's paths" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"===  vendor/a"* ]]
  [[ "$output" == *"--- a/file.txt"* ]]
  [[ "$output" == *"+local change"* ]]
  [[ "$output" != *".splice"* ]]
}

@test "diff: prints nothing for a splice with nothing to push" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_diff
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "diff: does not show upstream-only changes" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_diff
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "diff: a missing upstream branch compares against the monorepo's base" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"+local change"* ]]
  [[ "$output" != *"+seed"* ]]
}

@test "diff: on the base branch, a missing upstream branch shows everything as new" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q main
  git update-ref -d refs/splices/vendor/a/main
  seed_bare_repo "$upstream" "elsewhere" other
  fetch_splice "$monorepo" "$upstream" vendor/a
  git -C "$upstream" branch -D main >/dev/null
  fetch_splice "$monorepo" "$upstream" vendor/a
  run cmd_diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"+seed"* ]]
}

@test "diff: path arguments restrict output" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  commit_local "$monorepo" "vendor/a" "change in a"
  commit_local "$monorepo" "vendor/b" "change in b"
  run cmd_diff vendor/b
  [[ "$output" == *"===  vendor/b"* ]]
  [[ "$output" != *"vendor/a"* ]]
}

@test "diff: redirected output does not invoke the pager" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"

  run env GIT_PAGER=false "$BATS_TEST_DIRNAME/../git-splice" diff

  [ "$status" -eq 0 ]
  [[ "$output" == *"+local change"* ]]
  [[ "$output" != *$'\033['* ]]
}

@test "diff: output is colored while a pager is active" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"

  TERM=xterm run pipe_to_pager diff_paths cat main "" vendor/a

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033['* ]]
}

@test "diff: quitting the pager early does not report a splice failure" {
  diff_one() { return 141; }

  run diff_paths main "" vendor/a

  [ "$status" -eq 141 ]
  [[ "$output" != *"Failed:"* ]]
}

@test "diff: pager.splice=false overrides an exported pager" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config pager.splice false

  GIT_PAGER='missing-pager' run splice_pager

  [ "$status" -eq 0 ]
  [ "$output" = cat ]
}

@test "diff: an empty pager.splice value disables paging" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config pager.splice ""

  GIT_PAGER='missing-pager' run splice_pager

  [ "$status" -eq 0 ]
  [ "$output" = cat ]
}

@test "diff: a nonzero integer pager.splice value enables paging" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config pager.splice 2

  GIT_PAGER='custom-pager' run splice_pager

  [ "$status" -eq 0 ]
  [ "$output" = custom-pager ]
}

@test "diff: git --no-pager overrides pager.splice" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config pager.splice 'missing-pager'

  GIT_PAGER=cat run splice_pager

  [ "$status" -eq 0 ]
  [ "$output" = cat ]
}

@test "diff: pager startup failure is returned even when SIGPIPE is ignored" {
  # With SIGPIPE ignored, the producer doesn't die on the closed pipe but
  # fails its write (exit 1). The delay makes sure the pager is gone first.
  produce_diff() {
    sleep 0.3
    printf 'patch\n'
  }
  missing_pager_fails() {
    trap '' PIPE
    local rc=0
    pipe_to_pager produce_diff 'missing-pager-command' || rc=$?
    ((rc == 127))
  }

  run missing_pager_fails

  [ "$status" -eq 0 ]
}

@test "diff: pager startup failure is returned" {
  produce_diff() { printf 'patch\n'; }
  missing_pager_fails() {
    local rc=0
    pipe_to_pager produce_diff 'missing-pager-command' || rc=$?
    ((rc == 127))
  }

  run missing_pager_fails

  [ "$status" -eq 0 ]
}
