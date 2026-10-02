setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/up-to-date/setup'
  load 'scenarios/never-fetched/setup'
  load 'scenarios/shared-remote-url/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "fetch: brings every upstream branch into refs/splices/<path>/" {
  scenario_never_fetched "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "on a branch" feature
  cd "$monorepo"
  run cmd_fetch
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a fetched" ]
  git rev-parse --verify --quiet refs/splices/vendor/a/main
  git rev-parse --verify --quiet refs/splices/vendor/a/feature
  [ -z "$(git remote)" ]
}

@test "fetch: says when the branch this one syncs with moved" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  cd "$monorepo"
  run cmd_fetch vendor/a
  [[ "$output" == "ok   vendor/a fetched (main moved "*..*")" ]]
}

@test "fetch: prunes branches deleted upstream" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "on a branch" feature
  cd "$monorepo"
  cmd_fetch
  git -C "$upstream" branch -D feature >/dev/null
  cmd_fetch
  ! git rev-parse --verify --quiet refs/splices/vendor/a/feature
}

@test "fetch: a failing upstream is reported, the others still fetch" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/b/.splice splice.url "$BATS_TEST_TMPDIR/nowhere.git"
  git commit -q -am "break vendor/b"
  run cmd_fetch
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok   vendor/a fetched"* ]]
  [[ "$output" == *"Failed: vendor/b"* ]]
}

@test "fetch: honors url.<base>.insteadOf, since it works on URLs" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice splice.url "example:upstream.git"
  git commit -q -am "use a short URL"
  git config "url.$BATS_TEST_TMPDIR/.insteadOf" "example:"
  run cmd_fetch
  [ "$status" -eq 0 ]
}
