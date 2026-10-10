setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/up-to-date/push-ahead/setup'
  load 'scenarios/up-to-date/pull-ahead/setup'
  load 'scenarios/up-to-date/shared-remote-url/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "boundary: is the commit that spliced the library in" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_boundary vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "$(git rev-parse HEAD)" ]
}

@test "boundary: local commits since don't move it, nor does pushing them" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD^)" ]
  cmd_push vendor/a >/dev/null
  run cmd_boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD^)" ]
}

@test "boundary: a pull moves it to the pull's commit" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_merge vendor/a >/dev/null
  run cmd_boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD)" ]
  [ "$(git log -1 --format=%s "$output")" = "$(git log -1 --format=%s HEAD)" ]
}

@test "boundary: a commit that edits .splice by hand moves it too" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.origin.url https://example.com/a.git
  git commit -q -am "move vendor/a's upstream"
  run cmd_boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD)" ]
}

@test "boundary: works on a detached HEAD" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q --detach
  run cmd_boundary vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "$(git rev-parse HEAD^)" ]
}

@test "boundary: takes exactly one splice" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_boundary
  [ "$status" -eq 1 ]
  [[ "$output" == "usage: git splice boundary <path>"* ]]
  run cmd_boundary vendor/a vendor/b
  [ "$status" -eq 1 ]
  [[ "$output" == "usage: git splice boundary <path>"* ]]
  run cmd_boundary --all
  [ "$output" = "!!   boundary takes no --all" ]
  run cmd_boundary vendor
  [ "$output" = "!!   not a splice: vendor" ]
}
