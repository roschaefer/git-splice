setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/up-to-date/push-ahead/setup'
  load 'scenarios/up-to-date/pull-ahead/setup'
  load 'scenarios/up-to-date/shared-remote-url/setup'
  load 'scenarios/nested-splices/setup'
  load 'scenarios/init-new-upstream/setup'
  load 'scenarios/sync-model/after-pull/setup'
  load 'scenarios/up-to-date/squash-merged-pull/local-edit-in-the-squash/setup'
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
}

@test "boundary: a git mv of the folder doesn't move it: the rebuild follows the folder to its old path" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(cmd_boundary vendor/a)"
  mkdir libs
  git mv vendor/a libs/a
  git commit -q -m "move vendor/a"
  run cmd_boundary libs/a
  [ "$output" = "$before" ]
}

@test "boundary: a commit that edits .splice by hand moves it, if nothing is waiting to be pushed" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.origin.url https://example.com/a.git
  git commit -q -am "move vendor/a's upstream"
  run cmd_boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD)" ]
}

@test "boundary: a commit that edits .splice by hand doesn't move it past unpushed commits" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.origin.url https://example.com/a.git
  git commit -q -am "move vendor/a's upstream"
  run cmd_boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD~2)" ]
}

@test "boundary: a pull that merged unpushed commits leaves it before them" {
  scenario_after_pull "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD~4)" ]
  [ "$(git log --first-parent --format=%s "$output"..HEAD -- vendor/a)" = "$(printf '%s\n' 'splice: pull vendor/a from main at '"$(git -C "$upstream" rev-parse --short main)" d b)" ]
}

@test "boundary: stays before the merged commits after they're pushed, until a bump" {
  scenario_after_pull "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_push vendor/a >/dev/null
  cmd_merge vendor/a >/dev/null
  run cmd_boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD~4)" ]
  cmd_merge --bump vendor/a >/dev/null
  run cmd_boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD)" ]
}

@test "boundary: a squash merge of a pull and a local edit leaves it before the squash, whose edit push sends" {
  scenario_local_edit_in_the_squash "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD^)" ]
  [ "$(git log --format=%s "$output..HEAD" -- vendor/a)" = "feature (squash-merged)" ]
  [ "$(git log -1 --format=%s "$(rebuild_splice vendor/a)")" = "feature (squash-merged)" ]
}

@test "boundary: works on a detached HEAD" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q --detach
  run cmd_boundary vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "$(git rev-parse HEAD^)" ]
}

@test "boundary: of a nested splice, in the monorepo, is where the monorepo's rebuild of it starts" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_boundary vendor/a/b
  [ "$output" = "$(git rev-parse HEAD)" ]
  [ "$(git log -1 --format=%s "$output")" = "add vendor/a" ]
}

@test "boundary: of a nested splice, in a worktree of the upstream above, is where that upstream's rebuild of it starts" {
  scenario_nested_splices "$monorepo" "$upstream"
  git -C "$monorepo" worktree add -q --detach "$BATS_TEST_TMPDIR/a" refs/splices/upstream/main
  cd "$BATS_TEST_TMPDIR/a"
  run cmd_boundary b
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s "$output")" = "add b" ]
}

@test "boundary: a shallow clone that cuts off the last sync refuses, since the cut-off commit looks like it" {
  scenario_push_ahead "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "second local change"
  git clone -q --depth 1 "file://$monorepo" "$BATS_TEST_TMPDIR/shallow"
  cd "$BATS_TEST_TMPDIR/shallow"
  splice fetch vendor/a >/dev/null
  run splice boundary vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a: this shallow clone may cut off where its rebuild starts, at $(git rev-parse --short=7 HEAD) -- run 'git fetch --unshallow'" ]
}

@test "boundary: a shallow clone that cuts off the mount refuses" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  (cd "$monorepo" && splice init lib/a "$upstream" >/dev/null)
  commit_local "$monorepo" lib/a "local change"
  git clone -q --depth 1 "file://$monorepo" "$BATS_TEST_TMPDIR/shallow"
  cd "$BATS_TEST_TMPDIR/shallow"
  run splice boundary lib/a
  [ "$status" -eq 1 ]
  [[ "$output" == "!!   lib/a: this shallow clone may cut off where its rebuild starts"* ]]
}

@test "boundary: a shallow clone deep enough to have the commit before it works" {
  scenario_push_ahead "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "second local change"
  git clone -q --depth 4 "file://$monorepo" "$BATS_TEST_TMPDIR/shallow"
  cd "$BATS_TEST_TMPDIR/shallow"
  splice fetch vendor/a >/dev/null
  run splice boundary vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "$(git rev-parse HEAD~2)" ]
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
