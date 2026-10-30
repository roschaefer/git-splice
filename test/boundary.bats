setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load 'scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/01-pull-ahead/setup'
  load 'scenarios/04-upstreams/03-shared-remote-url/setup'
  load 'scenarios/05-nested-splices/01-nested-splices/setup'
  load 'scenarios/02-starting-a-splice/04-init-new-upstream/setup'
  load 'scenarios/01-everyday-sync/01-sync-model/01-after-pull/setup'
  load 'scenarios/03-branches-and-teamwork/03-squash-merged-pull/01-local-edit-in-the-squash/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "boundary: is the commit that spliced the library in" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice boundary vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "$(git rev-parse HEAD)" ]
}

@test "boundary: local commits since don't move it, nor does pushing them" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run splice boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD^)" ]
  splice push vendor/a >/dev/null
  run splice boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD^)" ]
}

@test "boundary: a pull moves it to the pull's commit" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  splice merge vendor/a >/dev/null
  run splice boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD)" ]
}

@test "boundary: a git mv of the folder doesn't move it: the rebuild follows the folder to its old path" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(splice boundary vendor/a)"
  mkdir libs
  git mv vendor/a libs/a
  git commit -q -m "move vendor/a"
  run splice boundary libs/a
  [ "$output" = "$before" ]
}

@test "boundary: a commit that edits .splice by hand moves it, if nothing is waiting to be pushed" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.origin.url https://example.com/a.git
  git commit -q -am "move vendor/a's upstream"
  run splice boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD)" ]
}

@test "boundary: a commit that edits .splice by hand doesn't move it past unpushed commits" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.origin.url https://example.com/a.git
  git commit -q -am "move vendor/a's upstream"
  run splice boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD~2)" ]
}

@test "boundary: a pull that merged unpushed commits leaves it before them" {
  scenario_after_pull "$monorepo" "$upstream"
  cd "$monorepo"
  run splice boundary lib
  [ "$output" = "$(git rev-parse HEAD~4)" ]
  [ "$(git log --first-parent --format=%s "$output"..HEAD -- lib)" = "$(printf '%s\n' e d b)" ]
}

@test "boundary: stays before the merged commits after they're pushed, until a bump" {
  scenario_after_pull "$monorepo" "$upstream"
  cd "$monorepo"
  splice push lib >/dev/null
  splice merge lib >/dev/null
  run splice boundary lib
  [ "$output" = "$(git rev-parse HEAD~4)" ]
  splice merge --bump lib >/dev/null
  run splice boundary lib
  [ "$output" = "$(git rev-parse HEAD)" ]
}

@test "boundary: a squash merge of a pull and a local edit leaves it before the squash, whose edit push sends" {
  scenario_local_edit_in_the_squash "$monorepo" "$upstream"
  cd "$monorepo"
  run splice boundary vendor/a
  [ "$output" = "$(git rev-parse HEAD^)" ]
  [ "$(git log --format=%s "$output..HEAD" -- vendor/a)" = "feature (squash-merged)" ]
  [ "$(git log -1 --format=%s "$(splice rebuild vendor/a)")" = "feature (squash-merged)" ]
}

@test "boundary: works on a detached HEAD" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q --detach
  run splice boundary vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "$(git rev-parse HEAD^)" ]
}

@test "boundary: of a nested splice, in the monorepo, is where the monorepo's rebuild of it starts" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  run splice boundary vendor/a/b
  [ "$output" = "$(git rev-parse HEAD)" ]
  [ "$(git log -1 --format=%s "$output")" = "add vendor/a" ]
}

@test "boundary: of a nested splice, in a worktree of the upstream above, is where that upstream's rebuild of it starts" {
  scenario_nested_splices "$monorepo" "$upstream"
  git -C "$monorepo" worktree add -q --detach "$BATS_TEST_TMPDIR/a" refs/splices/upstream/heads/main
  cd "$BATS_TEST_TMPDIR/a"
  run splice boundary b
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

@test "boundary: a shallow clone that cuts off a moved splice's history names the splice's path now" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  (cd "$monorepo" && splice init lib/a "$upstream" >/dev/null)
  (
    cd "$monorepo"
    mkdir libs pkg
    git mv lib/a libs/a
    git commit -q -m "move to libs"
    git mv libs/a pkg/a
    git commit -q -m "move to pkg"
  )
  git clone -q --depth 2 "file://$monorepo" "$BATS_TEST_TMPDIR/shallow"
  cd "$BATS_TEST_TMPDIR/shallow"
  run splice boundary pkg/a
  [ "$status" -eq 1 ]
  [[ "$output" == "!!   pkg/a: this shallow clone may cut off where its rebuild starts"* ]]
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
  run splice boundary
  [ "$status" -eq 1 ]
  [[ "$output" == *$'SYNOPSIS\n    git splice boundary <path>'* ]]
  run splice boundary vendor/a vendor/b
  [ "$status" -eq 1 ]
  [[ "$output" == *$'SYNOPSIS\n    git splice boundary <path>'* ]]
  run splice boundary --all
  [ "$output" = "!!   boundary takes no --all" ]
  run splice boundary vendor
  [ "$output" = "!!   not a splice: vendor" ]
}
