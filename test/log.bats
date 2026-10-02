setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/up-to-date/setup'
  load 'scenarios/diverged-common-ancestor/setup'
  load 'scenarios/feature-branch-changed/setup'
  load 'scenarios/merge-in-monorepo/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "log: marks what push publishes and what pull brings in, with the author" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_log
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "===  vendor/a (main)" ]
  [[ "$output" == *"< "*" local change  (Test <test@example.com>)"* ]]
  [[ "$output" == *"> "*" upstream change  (Test <test@example.com>)"* ]]
}

@test "log: marks the same change on both sides with =" {
  scenario_up_to_date "$monorepo" "$upstream"
  # The same new file, committed on both sides independently.
  commit_local "$monorepo" "vendor/a" "same change" same.txt
  seed_bare_repo "$upstream" "upstream change"
  seed_bare_repo "$upstream" "same change" main same.txt
  fetch_splice "$monorepo" "$upstream" vendor/a
  cd "$monorepo"
  run cmd_log
  [[ "$output" == *"= "*" same change"* ]]
  [[ "$output" == *"> "*" upstream change"* ]]
}

@test "log: a missing upstream branch lists everything a push would create" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_log
  [ "${lines[0]}" = "===  vendor/a (upstream has no 'feature' branch)" ]
  [[ "${lines[1]}" == "< "*" local change  (Test <test@example.com>)" ]]
  [ "${#lines[@]}" -eq 2 ]
}

@test "log: a merge in the monorepo shows as one commit" {
  scenario_merge_in_monorepo "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_log
  [[ "$output" == *"Merge branch 'main' into feature"* ]]
  [[ "$output" != *"main work"* ]]
}

@test "log: prints nothing but the header when up to date" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_log
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
