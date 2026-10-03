setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  local scenario
  for scenario in up-to-date clone-copied-content clone-differing-content \
    clone-on-feature-branch clone-without-commits; do
    load "scenarios/$scenario/setup"
  done
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

new_upstream() {
  make_bare_repo "$upstream" "${1:-main}"
  seed_bare_repo "$upstream" "seed" "${1:-main}"
  init_monorepo "$monorepo"
  cd "$monorepo"
}

@test "clone: splices upstream in as one commit with a .splice" {
  new_upstream
  local before
  before="$(git rev-parse HEAD)"
  run cmd_clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD^)" = "$before" ]
  [ "$(cat vendor/a/file.txt)" = seed ]
  [ "$(splice_config vendor/a url)" = "$upstream" ]
  [ "$(splice_config vendor/a commit)" = "$(git -C "$upstream" rev-parse main)" ]
  [ -z "$(splice_config vendor/a default-branch)" ]
  [ -z "$(git remote)" ]
  [ -z "$(git status --porcelain)" ]
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = up-to-date ]
}

@test "clone: names the folder after the repository by default" {
  new_upstream
  cmd_clone "$upstream"
  [ -f upstream/.splice ]
}

@test "clone: records upstream's default branch when it's named differently" {
  new_upstream master
  run cmd_clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a default-branch)" = master ]
  [[ "$output" == *"cloned"*"from master"* ]]
}

@test "clone: on a branch upstream lacks, uses upstream's default branch" {
  scenario_clone_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"upstream has no 'feature' branch -- using 'main'"* ]]
  classify_splice vendor/a feature
  [ "$SPLICE_STATE" = missing-branch ]
}

@test "clone: a folder with exactly upstream's content only gets a .splice" {
  scenario_clone_copied_content "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git show --name-only --format= HEAD)" = "vendor/a/.splice" ]
}

@test "clone: refuses a folder that differs from upstream" {
  scenario_clone_differing_content "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run cmd_clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a exists and differs"*"'--merge' keeps both"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "clone --merge: every differing file is a conflict, nothing is lost" {
  scenario_clone_differing_content "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_clone --merge "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT (add/add)"*"vendor/a/file.txt"* ]]
  [ "$(cat vendor/a/local.txt)" = "only local" ]
  [ "$(cat vendor/a/upstream.txt)" = "only upstream" ]
  [ "$(git status --porcelain vendor/a/file.txt)" = "AA vendor/a/file.txt" ]
  echo resolved >vendor/a/file.txt
  git add vendor/a/file.txt
  git commit -q --no-edit
  [ "$(git rev-list --parents -1 HEAD | wc -w)" -eq 2 ]
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = push ]
}

@test "clone: refuses an existing splice, a nested one, and an empty upstream" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_clone "$upstream" vendor/a
  [[ "$output" == *"vendor/a is a splice already"* ]]
  run cmd_clone "$upstream" vendor/a/inner
  [[ "$output" == *"nested splices are not supported"* ]]
  make_bare_repo "$BATS_TEST_TMPDIR/empty.git"
  run cmd_clone "$BATS_TEST_TMPDIR/empty.git" vendor/b
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no branches yet -- to publish vendor/b there, use 'git splice init"* ]]
}

@test "clone: refuses a monorepo without commits up front" {
  scenario_clone_without_commits "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no commits yet"* ]]
}

@test "clone: refuses a path that can't be part of a ref, before fetching" {
  scenario_clone_without_commits "$monorepo" "$upstream"
  cd "$monorepo"
  git commit -q --allow-empty -m "initial commit"
  run cmd_clone "$upstream" "my lib"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'my lib' can't be part of a Git ref name"* ]]
  [ -z "$(git for-each-ref refs/splices/)" ]
}

@test "clone: refuses an upstream that contains a .splice, at its root or deeper" {
  new_upstream
  seed_bare_repo "$upstream" "[splice]" main extra/.splice
  run cmd_clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"upstream has extra/.splice, and a splice can't contain another .splice"* ]]
  seed_bare_repo "$upstream" "[splice]" main .splice
  run cmd_clone "$upstream" vendor/a
  [[ "$output" == *"upstream has .splice,"* ]]
  [ -z "$(git ls-files vendor/a)" ]
}

@test "clone: an upstream file whose name only resembles .splice is content" {
  new_upstream
  seed_bare_repo "$upstream" "x" main xsplice
  seed_bare_repo "$upstream" "x" main docs/-splice
  run cmd_clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/xsplice)" = x ]
}

@test "clone: an upstream with only an empty commit works with every command" {
  make_bare_repo "$upstream"
  local tmp="$BATS_TEST_TMPDIR/seed"
  git clone -q "$upstream" "$tmp" 2>/dev/null
  git -C "$tmp" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m init
  git -C "$tmp" push -q origin HEAD:main
  init_monorepo "$monorepo"
  cd "$monorepo"
  cmd_clone "$upstream" vendor/a
  local cmd
  for cmd in status diff log "push vendor/a" "merge vendor/a"; do
    # shellcheck disable=SC2086
    run splice $cmd
    [ "$status" -eq 0 ]
  done
  run splice status
  [ "$output" = "ok   vendor/a -> main (up to date)" ]
}

@test "clone: refuses a path that is a file" {
  new_upstream
  echo x >vendor
  git add vendor && git commit -q -m "a file"
  run cmd_clone "$upstream" vendor
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor is a file, not a folder"* ]]
  ! git rev-parse --quiet --verify CHERRY_PICK_HEAD
}

@test "clone: asks for the monorepo's default branch when upstream's is named differently" {
  new_upstream master
  git config --unset init.defaultBranch
  run cmd_clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"upstream's default branch is 'master', and the monorepo's can't be determined"* ]]
  git config init.defaultBranch main
  run cmd_clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
}
