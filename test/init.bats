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
  [ "$(git config --file lib/a/.splice upstream.origin.url)" = "$upstream" ]
  [ -z "$(splice_config lib/a commit)" ]
}

@test "init: the first push sends the folder as it was at init, as one commit" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_init lib/a "$upstream"
  run cmd_push lib/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log --format=%s main)" = "splice: init lib/a" ]
  classify_splice lib/a main
  [ "$SPLICE_STATE" = up-to-date ]
}

@test "init: the first push records the key before it pushes, so a failure to record it pushes nothing" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_init lib/a "$upstream" >/dev/null
  mkdir .git/splice-keys.lock
  UPSTREAM_KEYS_LOCK_TRIES=1
  run cmd_push lib/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"another git splice is recording an upstream key"* ]]
  [ -z "$(git -C "$upstream" for-each-ref refs/heads)" ]
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
  run cmd_push lib/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log -1 --format=%s master)" = "splice: init lib/a" ]
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
  [ "$(git config --file lib/a/.splice upstream.origin.url)" = "$upstream" ]
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

@test "init: on a path that had another upstream, the first push publishes everything" {
  scenario_up_to_date "$monorepo" "$upstream"
  local new="$BATS_TEST_TMPDIR/new.git"
  make_bare_repo "$new"
  cd "$monorepo"
  git rm -q vendor/a/.splice && git commit -q -m "unsplice vendor/a"
  splice init vendor/a "$new" >/dev/null
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: pushed"* ]]
  [ "$(git -C "$new" show main:file.txt)" = "$(git show HEAD:vendor/a/file.txt)" ]
}

@test "init: drops refs fetched before from an upstream that is empty now" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "seed"
  cd "$monorepo"
  git fetch -q "$upstream" "+refs/heads/*:$(upstream_refs "$upstream")*"
  git -C "$upstream" update-ref -d refs/heads/main
  run cmd_init lib/a "$upstream"
  [ "$status" -eq 0 ]
  [ -z "$(git for-each-ref "$(upstream_refs "$upstream")")" ]
  classify_splice lib/a main
  [ "$SPLICE_STATE" = missing-branch ]
}
