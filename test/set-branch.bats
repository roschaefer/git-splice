setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load 'scenarios/01-everyday-sync/02-up-to-date/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/setup'
  load 'scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/setup'
  load 'scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/01-feature-branch-changed/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "set-branch: push --branch --set-branch remembers the upstream branch for the current branch, by the upstream's key, and the next push goes there" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run splice push --branch development --set-branch vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a: 'feature' syncs with 'development' from now on"* ]]
  [ "$(git config --local --get-all branch.feature.splice)" = "$(splice key vendor/a):development" ]
  commit_local "$monorepo" vendor/a "another change"
  run splice push vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log -1 --format=%s development)" = "another change" ]
  ! git -C "$upstream" rev-parse --verify --quiet feature
}

@test "set-branch: status marks the remembered branch as set locally, which another clone doesn't have" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  splice push --branch development --set-branch vendor/a >/dev/null 2>&1
  run splice status
  [ "$output" = "$(cat <<'EOF'
On branch feature

  up to date  vendor/a -> development  set for feature, local
EOF
  )" ]
}

@test "set-branch: a second --set-branch replaces the remembered branch" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  splice push --branch development --set-branch vendor/a >/dev/null 2>&1
  splice push --branch review --set-branch vendor/a >/dev/null 2>&1
  [ "$(git config --local --get-all branch.feature.splice)" = "$(splice key vendor/a):review" ]
}

@test "set-branch: needs --branch, which names the branch it remembers" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run splice push --set-branch vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --set-branch remembers the branch --branch names -- add --branch <name>" ]
  ! git config --local --get-all branch.feature.splice
}

@test "set-branch: pull --branch --set-branch remembers it, and a plain pull takes the branch's next change in" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "development change" development
  cd "$monorepo"
  run splice pull --branch development --set-branch vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a: 'feature' syncs with 'development' from now on"* ]]
  seed_bare_repo "$upstream" "next development change" development
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(tail -1 vendor/a/file.txt)" = "next development change" ]
}

@test "set-branch: on the monorepo's default branch, the remembered branch wins over upstream's default branch" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  splice push --branch development --set-branch vendor/a >/dev/null 2>&1
  run splice status
  [ "${lines[1]}" = "  up to date  vendor/a -> development  set for main, local" ]
  [ "$(git -C "$upstream" log -1 --format=%s development)" = "local change" ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" != "local change" ]
}

@test "set-branch: renaming the upstream's key renames it in the remembered branches" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  splice push --branch development --set-branch vendor/a >/dev/null 2>&1
  splice key vendor/a renamed >/dev/null
  [ "$(git config --local --get-all branch.feature.splice)" = "renamed:development" ]
  run splice status
  [ "${lines[1]}" = "  up to date  vendor/a -> development  set for feature, local" ]
}

@test "set-branch: 'git branch -m' takes the remembered branch along, as Git does its own tracking" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  splice push --branch development --set-branch vendor/a >/dev/null 2>&1
  git branch -m feature studio
  run splice status
  [ "${lines[1]}" = "  up to date  vendor/a -> development  set for studio, local" ]
}

@test "set-branch: a pull from a remembered branch upstream deleted fails, naming where it's remembered" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  splice push --branch development --set-branch vendor/a >/dev/null 2>&1
  git -C "$upstream" branch -q -D development
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: upstream has no 'development' branch, which branch.feature.splice remembers -- pull --branch <name> --set-branch remembers another"* ]]
}
