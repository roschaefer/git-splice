setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/init-new-upstream/setup'
  load 'scenarios/up-to-date/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "init: commits only the .splice file" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  echo "staged, not committed" >other.txt
  git add other.txt
  run cmd_init lib/a "$upstream"
  [ "$status" -eq 0 ]
  [ "$(git show --name-only --format= HEAD)" = "lib/a/.splice" ]
  [ "$(git status --porcelain)" = "A  other.txt" ]
  [ "$(splice_config lib/a url)" = "$upstream" ]
  [ -z "$(splice_config lib/a commit)" ]
}

@test "init: the first push sends the folder's history" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_init lib/a "$upstream"
  run cmd_push lib/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log --format=%s main)" = "second version"$'\n'"first version" ]
  classify_splice lib/a main
  [ "$SPLICE_STATE" = up-to-date ]
}

@test "init: refuses an upstream that has commits" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "seed"
  cd "$monorepo"
  run cmd_init lib/a "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"has commits already -- to combine them with lib/a, use 'git splice clone --merge"* ]]
}

@test "init: refuses a folder that isn't committed, and an existing splice" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  make_bare_repo "$BATS_TEST_TMPDIR/empty.git"
  run cmd_init nope "$BATS_TEST_TMPDIR/empty.git"
  [[ "$output" == *"no committed folder here"* ]]
  run cmd_init vendor/a "$BATS_TEST_TMPDIR/empty.git"
  [[ "$output" == *"vendor/a is a splice already"* ]]
}

@test "init: refuses an unreachable upstream" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_init lib/a "$BATS_TEST_TMPDIR/nowhere.git"
  [ "$status" -eq 1 ]
  [[ "$output" == *"can't reach"* ]]
}

@test "init: records an empty upstream's default branch when it's named differently" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  rm -rf "$upstream"
  make_bare_repo "$upstream" master
  cd "$monorepo"
  cmd_init lib/a "$upstream"
  [ "$(splice_config lib/a default-branch)" = master ]
  cmd_push lib/a
  [ "$(git -C "$upstream" log -1 --format=%s master)" = "second version" ]
  ! git -C "$upstream" rev-parse --verify --quiet main
}

@test "init: refuses a detached HEAD and a conflict in progress" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q --detach
  run cmd_init lib/a "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"detached HEAD"* ]]
  git checkout -q main
  git update-ref CHERRY_PICK_HEAD HEAD
  run cmd_init lib/a "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"in progress"* ]]
  [ -z "$(git status --porcelain lib/a)" ]
}


@test "init: commits .splice even when an ignore rule matches it" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  echo ".*" >.git/info/exclude
  cmd_init lib/a "$upstream"
  [ "$(splice_config lib/a url)" = "$upstream" ]
}

@test "init: refuses a .splice that is a dangling symlink, and writes nothing" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  ln -s "$BATS_TEST_TMPDIR/outside" lib/a/.splice
  run cmd_init lib/a "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lib/a/.splice exists, but isn't committed"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/outside" ]
}
