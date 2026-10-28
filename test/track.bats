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

# Splices vendor/b from a second upstream, whose key "upstream.de" starts
# with vendor/a's key "upstream".
add_second_upstream() {
  local second="$BATS_TEST_TMPDIR/upstream.de.git"
  make_bare_repo "$second"
  seed_bare_repo "$second" "seed"
  add_splice "$monorepo" "$second" vendor/b
  commit_local "$monorepo" vendor/b "local change"
  (cd "$monorepo" && splice fetch vendor/b >/dev/null 2>&1)
}

@test "track: push --branch --track tracks the upstream branch on the current branch, by the upstream's key, and the next push goes there" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run splice push --branch development --track vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a: 'feature' tracks 'development' from now on"* ]]
  [ "$(git config --local --get-all branch.feature.splice)" = "$(splice key vendor/a):development" ]
  commit_local "$monorepo" vendor/a "another change"
  run splice push vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log -1 --format=%s development)" = "another change" ]
  ! git -C "$upstream" rev-parse --verify --quiet feature
}

@test "track: status marks the tracked branch as local, which another clone doesn't have" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  splice push --branch development --track vendor/a >/dev/null 2>&1
  run splice status
  [ "$output" = "$(cat <<'EOF'
On branch feature

  up to date  vendor/a -> development  tracked on feature, local
EOF
  )" ]
}

@test "track: a second --track replaces the tracked branch" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  splice push --branch development --track vendor/a >/dev/null 2>&1
  splice push --branch review --track vendor/a >/dev/null 2>&1
  [ "$(git config --local --get-all branch.feature.splice)" = "$(splice key vendor/a):review" ]
}

@test "track: needs --branch, which names the branch it tracks" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run splice push --track vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --track tracks the branch --branch names -- add --branch <name>" ]
  ! git config --local --get-all branch.feature.splice
}

@test "track: pull --branch --track tracks it, and a plain pull takes the branch's next change in" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "development change" development
  cd "$monorepo"
  run splice pull --branch development --track vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a: 'feature' tracks 'development' from now on"* ]]
  seed_bare_repo "$upstream" "next development change" development
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(tail -1 vendor/a/file.txt)" = "next development change" ]
}

@test "track: on the monorepo's default branch, the tracked branch wins over upstream's default branch" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  splice push --branch development --track vendor/a >/dev/null 2>&1
  run splice status
  [ "${lines[1]}" = "  up to date  vendor/a -> development  tracked on main, local" ]
  [ "$(git -C "$upstream" log -1 --format=%s development)" = "local change" ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" != "local change" ]
}

@test "track: renaming the upstream's key renames it in the tracked branches" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  splice push --branch development --track vendor/a >/dev/null 2>&1
  splice key vendor/a renamed >/dev/null
  [ "$(git config --local --get-all branch.feature.splice)" = "renamed:development" ]
  run splice status
  [ "${lines[1]}" = "  up to date  vendor/a -> development  tracked on feature, local" ]
}

@test "track: each upstream tracks its own branch on the same monorepo branch" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  add_second_upstream
  cd "$monorepo"
  splice push --branch development --track vendor/a >/dev/null 2>&1
  splice push --branch review --track vendor/b >/dev/null 2>&1
  [ "$(git config --local --get-all branch.feature.splice)" = "$(printf '%s\n' upstream:development upstream.de:review)" ]
  run splice status
  [ "$output" = "$(cat <<'EOF'
On branch feature

  up to date  vendor/a -> development  tracked on feature, local
  up to date  vendor/b -> review       tracked on feature, local
EOF
  )" ]
}

@test "track: renaming a key renames it on every monorepo branch, and leaves keys it's only a prefix of alone" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  add_second_upstream
  cd "$monorepo"
  splice push --branch development --track vendor/a >/dev/null 2>&1
  splice push --branch review --track vendor/b >/dev/null 2>&1
  git switch -q -c other
  splice push --branch development --track vendor/a >/dev/null 2>&1
  splice key vendor/a renamed >/dev/null
  [ "$(git config --local --get-all branch.feature.splice)" = "$(printf '%s\n' renamed:development upstream.de:review)" ]
  [ "$(git config --local --get-all branch.other.splice)" = renamed:development ]
}

@test "track: 'git branch -m' takes the tracked branch along, as Git does its own tracking" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  splice push --branch development --track vendor/a >/dev/null 2>&1
  git branch -m feature studio
  run splice status
  [ "${lines[1]}" = "  up to date  vendor/a -> development  tracked on studio, local" ]
}

@test "track: a pull from a tracked branch upstream deleted fails, naming where it's tracked" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  splice push --branch development --track vendor/a >/dev/null 2>&1
  git -C "$upstream" branch -q -D development
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: upstream has no 'development' branch, which branch.feature.splice tracks -- 'git splice fetch --branch <name> --track vendor/a' tracks another, '--no-track' none"* ]]
}

@test "track: fetch --branch --track tracks a branch without a pull or push, and status compares with it" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "development change" development
  cd "$monorepo"
  local head
  head="$(git rev-parse HEAD)"
  run splice fetch --branch development --track vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a: 'feature' tracks 'development' from now on"* ]]
  [ "$(git rev-parse HEAD)" = "$head" ]
  run splice status
  [ "$output" = "$(cat <<'EOF'
On branch feature

  ahead 1, behind 1  vendor/a -> development  tracked on feature, local
EOF
  )" ]
}

@test "track: fetch --track refuses a branch upstream doesn't have" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run splice fetch --branch nonexistent --track vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: upstream has no 'nonexistent' branch to track"* ]]
  ! git config --local --get-all branch.feature.splice
}

@test "track: fetch --no-track stops tracking, so the splice syncs with the branch named like the current one again" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  add_second_upstream
  cd "$monorepo"
  splice fetch --branch main --track vendor/a >/dev/null 2>&1
  splice fetch --branch main --track vendor/b >/dev/null 2>&1
  run splice fetch --no-track vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a: 'feature' no longer tracks 'main'"* ]]
  [ "$(git config --local --get-all branch.feature.splice)" = upstream.de:main ]
  run splice status vendor/a
  [ "$output" = "$(cat <<'EOF'
On branch feature

  new, ahead 1  vendor/a  push creates the branch
EOF
  )" ]
}

@test "track: fetch --no-track without a tracked branch says so" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run splice fetch --no-track vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a: 'feature' tracks no branch of its upstream"* ]]
}

@test "track: --track and --no-track together are refused" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run splice fetch --branch main --track --no-track vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --track and --no-track contradict each other -- give one" ]
}

@test "track: push --track doesn't track a branch the push didn't create, and keeps the tracked one" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  splice fetch --branch main --track vendor/a >/dev/null 2>&1
  run splice push --branch development --track vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: upstream has no 'development' branch to track -- the push didn't create it"* ]]
  [ "$(git config --local --get-all branch.feature.splice)" = "$(splice key vendor/a):main" ]
}
