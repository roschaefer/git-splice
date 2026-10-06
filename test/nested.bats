setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/nested-splices/setup'
  load 'scenarios/up-to-date/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  inner="$BATS_TEST_TMPDIR/upstream-b.git"
}

# Clones the outer upstream into $outer_work, where b is a splice at b/,
# and cds there.
work_in_outer_upstream() {
  outer_work="$BATS_TEST_TMPDIR/outer-work"
  git clone -q "$upstream" "$outer_work"
  cd "$outer_work"
  git config user.name "Test"
  git config user.email "test@example.com"
}

@test "nested: status shows the outer and the inner splice" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  run splice status
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ok   vendor/a -> main (up to date)" ]
  [ "${lines[1]}" = "ok   vendor/a/b -> main (up to date)" ]
}

@test "nested: push of the inner splice sends its files without its .splice" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push vendor/a/b
  [ "$(git -C "$inner" ls-tree --name-only main)" = "file.txt" ]
  [ "$(git -C "$inner" show main:file.txt)" = "$(git show HEAD:vendor/a/b/file.txt)" ]
}

@test "nested: push of the outer splice sends the inner one's files and its .splice" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push vendor/a
  [ "$(git -C "$upstream" ls-tree -r --name-only main)" = $'b/.splice\nb/file.txt\nfile.txt' ]
  [ "$(git -C "$upstream" rev-parse main:b)" = "$(git rev-parse HEAD:vendor/a/b)" ]
}

@test "nested: after both pushes, the outer upstream's own clone sees the inner splice up to date" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push --all
  work_in_outer_upstream
  splice fetch b
  run splice status b
  [ "$output" = "ok   b -> main (up to date)" ]
}

@test "nested: a pull of the inner splice reaches the outer upstream with the next push of the outer one" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$inner" "b upstream change"
  cd "$monorepo"
  splice pull vendor/a/b
  splice push vendor/a
  [ "$(git -C "$upstream" show main:b/.splice | git config --file - splice.commit)" = "$(git -C "$inner" rev-parse main)" ]
  [ "$(git -C "$upstream" rev-parse main:b/file.txt)" = "$(git -C "$inner" rev-parse main:file.txt)" ]
}

@test "nested: cloning an upstream that contains a .splice makes its folder a splice" {
  scenario_nested_splices "$BATS_TEST_TMPDIR/first" "$upstream"
  init_monorepo "$monorepo"
  cd "$monorepo"
  splice clone "$upstream" lib
  [ "$(git show HEAD:lib/b/.splice)" = "$(git -C "$upstream" show main:b/.splice)" ]
  run splice status
  [ "${lines[0]}" = "ok   lib -> main (up to date)" ]
  [ "${lines[1]}" = "??   lib/b -> main (never fetched -- run 'git splice fetch lib/b')" ]
}

@test "nested: a merge brings in a .splice the upstream added, and the folder becomes a splice" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "$(printf '[upstream "origin"]\n\turl = %s' "$upstream")" main extra/.splice
  cd "$monorepo"
  splice pull vendor/a
  discover_splices
  [ "${ALL_PATHS[*]}" = "vendor/a vendor/a/extra" ]
}

@test "nested: clone and init make a splice inside an existing one" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  splice clone "$inner" vendor/a/c
  mkdir vendor/a/d && echo d >vendor/a/d/file.txt
  git add vendor/a/d && git commit -q -m "add d"
  make_bare_repo "$BATS_TEST_TMPDIR/d.git"
  splice init vendor/a/d "$BATS_TEST_TMPDIR/d.git"
  discover_splices
  [ "${ALL_PATHS[*]}" = "vendor/a vendor/a/b vendor/a/c vendor/a/d" ]
}

@test "nested: init makes a splice around an existing one" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  make_bare_repo "$BATS_TEST_TMPDIR/vendor.git"
  splice init vendor "$BATS_TEST_TMPDIR/vendor.git"
  splice push vendor
  [ "$(git -C "$BATS_TEST_TMPDIR/vendor.git" ls-tree -r --name-only main)" = $'a/.splice\na/b/.splice\na/b/file.txt\na/file.txt' ]
}

@test "nested: a pull of the outer splice keeps an inner .splice its upstream doesn't have" {
  scenario_up_to_date "$monorepo" "$upstream"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "b seed"
  cd "$monorepo"
  splice clone "$inner" vendor/a/b
  seed_bare_repo "$upstream" "upstream change"
  splice pull vendor/a
  [ "$(git show HEAD:vendor/a/file.txt)" = $'seed\nupstream change' ]
  git cat-file -e HEAD:vendor/a/b/.splice
}

@test "nested: a pull of the outer splice that moves the inner one's synced commit keeps its unpushed commits" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$inner" "b upstream change" main other.txt
  work_in_outer_upstream
  splice pull b
  git push -q origin main
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a/b fetched"* ]]
  run splice status vendor/a/b
  [ "$output" = "ok   vendor/a/b -> main (push: ahead 2)" ]
  splice push vendor/a/b
  run git -C "$inner" log --format=%s main
  [[ "$output" == *"b local"* ]]
  [ "$(git -C "$inner" show main:file.txt)" = $'b seed\nb local' ]
  [ "$(git -C "$inner" show main:other.txt)" = "b upstream change" ]
}

@test "nested: both sides pulling the inner splice make the next pull of the outer one conflict" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$inner" "b change 1" main other.txt
  cd "$monorepo"
  splice pull vendor/a/b
  seed_bare_repo "$inner" "b change 2" main other.txt
  work_in_outer_upstream
  splice pull b
  git push -q origin main
  cd "$monorepo"
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT (content): Merge conflict in vendor/a/b/.splice"* ]]
  [[ "$output" == *"vendor/a: conflict -- resolve it"* ]]
}

@test "nested: that conflict resolves to the outer upstream's side of the inner folder, if it has no unpushed changes" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$inner" "b change 1" main other.txt
  cd "$monorepo"
  splice pull vendor/a/b
  seed_bare_repo "$inner" "b change 2" main other.txt
  work_in_outer_upstream
  splice pull b
  git push -q origin main
  cd "$monorepo"
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  git checkout --theirs -- vendor/a/b
  git add vendor/a/b
  git commit -q --no-edit
  run splice status
  [ "${lines[0]}" = "ok   vendor/a -> main (up to date)" ]
  [ "${lines[1]}" = "ok   vendor/a/b -> main (up to date)" ]
}

@test "nested: pull --all skips an inner splice that the pull of the outer one removed" {
  scenario_nested_splices "$monorepo" "$upstream"
  work_in_outer_upstream
  git rm -q b/.splice
  git commit -q -m "b is part of a"
  git push -q origin main
  cd "$monorepo"
  run splice pull --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a/b: not a splice any more -- nothing to pull"* ]]
  ! git cat-file -e HEAD:vendor/a/b/.splice
}

@test "nested: pull takes the outer splice first, whose pull moves the inner one's synced commit" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$inner" "b change 1" main other.txt
  work_in_outer_upstream
  splice pull b
  git push -q origin main
  seed_bare_repo "$inner" "b change 2" main other.txt
  cd "$monorepo"
  run splice pull vendor/a/b vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: pulled"*"vendor/a/b: pulled"* ]]
  [ "$(git show HEAD:vendor/a/b/other.txt)" = $'b change 1\nb change 2' ]
}
