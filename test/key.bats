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

@test "key: prints the key of the splice's upstream, for its refs" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_key vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = upstream ]
  git rev-parse --verify --quiet "refs/splices/$output/main"
}

@test "key: an upstream never fetched has none yet, and asking doesn't record one" {
  scenario_never_fetched "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_key vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a: its upstream has no key yet -- 'git splice fetch vendor/a' records one" ]
  [ -z "$(git config --local --get-regexp '^splice\.' || true)" ]
}

@test "key: renaming moves the refs and the config entry" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "on a branch" feature/x
  cd "$monorepo"
  cmd_fetch >/dev/null
  run cmd_key vendor/a lib
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: renamed key 'upstream' to 'lib'" ]
  [ "$(git for-each-ref --format='%(refname)' refs/splices/)" = "refs/splices/lib/feature/x"$'\n'"refs/splices/lib/main" ]
  [ "$(git config --local splice.lib.url)" = "$upstream" ]
  [ -z "$(git config --local splice.upstream.url || true)" ]
  run "$BATS_TEST_DIRNAME/../git-splice" status vendor/a
  [ "$output" = "ok   vendor/a -> main (up to date)" ]
}

@test "key: a rename applies to every splice with the same URL" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_key vendor/a lib >/dev/null
  run cmd_key vendor/b
  [ "$output" = lib ]
}

@test "key: refuses an invalid key, or one that's taken" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --local splice.other.url https://example.com/other.git
  run cmd_key vendor/a Lib
  [ "$status" -eq 1 ]
  [[ "$output" == "!!   'Lib' isn't a valid key -- "* ]]
  run cmd_key vendor/a other
  [ "$status" -eq 1 ]
  [[ "$output" == "!!   key 'other' is taken -- "* ]]
  [ "$(cmd_key vendor/a)" = upstream ]
}

@test "key: renaming to the same key changes nothing" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_key vendor/a upstream
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: key is 'upstream' already" ]
}

@test "key: refuses a path that isn't a splice" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_key vendor
  [ "$status" -eq 1 ]
  [ "$output" = "!!   not a splice: vendor" ]
}
