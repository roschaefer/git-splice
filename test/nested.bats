setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/nested-splices/setup'
  load 'scenarios/nested-default-branch/setup'
  load 'scenarios/up-to-date/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  upstream_b="$BATS_TEST_TMPDIR/upstream-b.git"
}

# Clones a's upstream into $a_work, where b is a splice at b/, and cds
# there.
work_in_upstream_a() {
  a_work="$BATS_TEST_TMPDIR/a-work"
  git clone -q "$upstream" "$a_work"
  cd "$a_work"
  git config user.name "Test"
  git config user.email "test@example.com"
}

@test "nested: status shows a splice and the one below it" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  run splice status
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ok   vendor/a -> main (up to date)" ]
  [ "${lines[1]}" = "ok   vendor/a/b -> main (up to date)" ]
}

@test "nested: push of the splice below sends its files without its .splice" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push vendor/a/b
  [ "$(git -C "$upstream_b" ls-tree --name-only main)" = "file.txt" ]
  [ "$(git -C "$upstream_b" show main:file.txt)" = "$(git show HEAD:vendor/a/b/file.txt)" ]
}

@test "nested: push of the splice above sends the files and the .splice of the one below" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push vendor/a
  [ "$(git -C "$upstream" ls-tree -r --name-only main)" = $'b/.splice\nb/file.txt\nfile.txt' ]
  [ "$(git -C "$upstream" rev-parse main:b)" = "$(git rev-parse HEAD:vendor/a/b)" ]
}

@test "nested: after both pushes, a clone of a's upstream sees b up to date" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push --all
  work_in_upstream_a
  splice fetch b
  run splice status b
  [ "$output" = "ok   b -> main (up to date)" ]
}

@test "nested: a pull of b reaches a's upstream with the next push of a" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" "b upstream change"
  cd "$monorepo"
  splice pull vendor/a/b
  splice push vendor/a
  [ "$(git -C "$upstream" show main:b/.splice | git config --file - splice.commit)" = "$(git -C "$upstream_b" rev-parse main)" ]
  [ "$(git -C "$upstream" rev-parse main:b/file.txt)" = "$(git -C "$upstream_b" rev-parse main:file.txt)" ]
}

@test "nested: a .splice below without default-branch follows the default branch of the splice above" {
  scenario_nested_default_branch "$monorepo" "$upstream"
  cd "$monorepo"
  splice clone "$upstream" vendor/a
  splice fetch
  run splice status
  [ "${lines[0]}" = "ok   vendor/a -> master (up to date)" ]
  [ "${lines[1]}" = "ok   vendor/a/b -> master (up to date)" ]
}

@test "nested: clone inside a splice records default-branch only where it differs from the splice above's" {
  scenario_nested_default_branch "$monorepo" "$upstream"
  local upstream_main="$BATS_TEST_TMPDIR/main.git"
  make_bare_repo "$upstream_main" main
  seed_bare_repo "$upstream_main" "main seed" main
  cd "$monorepo"
  splice clone "$upstream" vendor/a
  cmd_clone "$upstream_b" vendor/a/c
  cmd_clone "$upstream_main" vendor/a/d
  [ -z "$(splice_config vendor/a/c default-branch)" ]
  [ "$(splice_config vendor/a/d default-branch)" = main ]
  [ "$(upstream_branch_for vendor/a/c main)" = master ]
  [ "$(upstream_branch_for vendor/a/d main)" = main ]
}

@test "nested: clone inside a splice refuses when the monorepo's default branch can't be determined, though the splice above's can" {
  scenario_nested_default_branch "$monorepo" "$upstream"
  cd "$monorepo"
  splice clone "$upstream" vendor/a
  git config --unset init.defaultBranch
  run cmd_clone "$upstream_b" vendor/a/c
  [ "$status" -eq 1 ]
  [[ "$output" == *"upstream's default branch is 'master', and the monorepo's can't be determined"* ]]
  [ ! -e vendor/a/c/.splice ]
}

@test "nested: init inside a splice refuses when the monorepo's default branch can't be determined, though the splice above's can" {
  scenario_nested_default_branch "$monorepo" "$upstream"
  local empty_master="$BATS_TEST_TMPDIR/empty-master.git"
  make_bare_repo "$empty_master" master
  cd "$monorepo"
  splice clone "$upstream" vendor/a
  commit_local "$monorepo" vendor/a/e "e's first version"
  git config --unset init.defaultBranch
  run cmd_init vendor/a/e "$empty_master"
  [ "$status" -eq 1 ]
  [[ "$output" == *"upstream's default branch is 'master', and the monorepo's can't be determined"* ]]
  [ ! -e vendor/a/e/.splice ]
}

@test "nested: init inside a splice records default-branch only where it differs from the splice above's" {
  scenario_nested_default_branch "$monorepo" "$upstream"
  local empty_master="$BATS_TEST_TMPDIR/empty-master.git"
  make_bare_repo "$empty_master" master
  cd "$monorepo"
  splice clone "$upstream" vendor/a
  commit_local "$monorepo" vendor/a/e "e's first version"
  cmd_init vendor/a/e "$empty_master"
  [ -z "$(splice_config vendor/a/e default-branch)" ]
  [ "$(upstream_branch_for vendor/a/e main)" = master ]
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
  splice clone "$upstream_b" vendor/a/c
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

@test "nested: a pull of a keeps a .splice below it that a's upstream doesn't have" {
  scenario_up_to_date "$monorepo" "$upstream"
  make_bare_repo "$upstream_b"
  seed_bare_repo "$upstream_b" "b seed"
  cd "$monorepo"
  splice clone "$upstream_b" vendor/a/b
  seed_bare_repo "$upstream" "upstream change"
  splice pull vendor/a
  [ "$(git show HEAD:vendor/a/file.txt)" = $'seed\nupstream change' ]
  git cat-file -e HEAD:vendor/a/b/.splice
}

@test "nested: a pull of a that moves b's synced commit keeps b's unpushed commits" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" "b upstream change" main other.txt
  work_in_upstream_a
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
  run git -C "$upstream_b" log --format=%s main
  [[ "$output" == *"b local"* ]]
  [ "$(git -C "$upstream_b" show main:file.txt)" = $'b seed\nb local' ]
  [ "$(git -C "$upstream_b" show main:other.txt)" = "b upstream change" ]
}

@test "nested: both sides pulling b make the next pull of a conflict" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" "b change 1" main other.txt
  cd "$monorepo"
  splice pull vendor/a/b
  seed_bare_repo "$upstream_b" "b change 2" main other.txt
  work_in_upstream_a
  splice pull b
  git push -q origin main
  cd "$monorepo"
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT (content): Merge conflict in vendor/a/b/.splice"* ]]
  [[ "$output" == *"vendor/a: conflict -- resolve it"* ]]
}

@test "nested: that conflict resolves to the side of a's upstream, if b has no unpushed changes" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" "b change 1" main other.txt
  cd "$monorepo"
  splice pull vendor/a/b
  seed_bare_repo "$upstream_b" "b change 2" main other.txt
  work_in_upstream_a
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

@test "nested: pull --all skips b if the pull of a removed it" {
  scenario_nested_splices "$monorepo" "$upstream"
  work_in_upstream_a
  git rm -q b/.splice
  git commit -q -m "b is part of a"
  git push -q origin main
  cd "$monorepo"
  run splice pull --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a/b: not a splice any more -- nothing to pull"* ]]
  ! git cat-file -e HEAD:vendor/a/b/.splice
}

@test "nested: pull goes top-down: a first, whose pull moves b's synced commit" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" "b change 1" main other.txt
  work_in_upstream_a
  splice pull b
  git push -q origin main
  seed_bare_repo "$upstream_b" "b change 2" main other.txt
  cd "$monorepo"
  run splice pull vendor/a/b vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: pulled"*"vendor/a/b: pulled"* ]]
  [ "$(git show HEAD:vendor/a/b/other.txt)" = $'b change 1\nb change 2' ]
}

@test "nested: top-down puts each splice after the ones above it, bottom-up before them, and keeps the order given otherwise" {
  run splices_in_order top-down deep/x/y other deep/x z
  [ "$output" = $'deep/x\ndeep/x/y\nother\nz' ]
  run splices_in_order bottom-up deep/x/y other deep/x z
  [ "$output" = $'deep/x/y\ndeep/x\nother\nz' ]
}

@test "nested: subtrees under the same splice keep the order of their first path too" {
  run splices_in_order top-down a/b/d a/c a/b a
  [ "$output" = $'a\na/b\na/b/d\na/c' ]
  run splices_in_order bottom-up a/b/d a/c a/b a
  [ "$output" = $'a/b/d\na/b\na/c\na' ]
}

@test "nested: pull skips the splice above when the fetch of the one below fails" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "a change"
  cd "$monorepo"
  git config --file vendor/a/b/.splice upstream.origin.url "$BATS_TEST_TMPDIR/nowhere.git"
  git commit -q -am "break vendor/a/b"
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: not pulled, since vendor/a/b below it wasn't fetched -- 'git splice merge vendor/a' merges what was fetched anyway"* ]]
  [[ "$output" == *"Not fetched: vendor/a/b"* ]]
  [ "$(git log -1 --format=%s)" = "break vendor/a/b" ]
}

@test "nested: pull skips the splice below when the fetch of the one above fails" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" "b change" main other.txt
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.origin.url "$BATS_TEST_TMPDIR/nowhere.git"
  git commit -q -am "break vendor/a"
  run splice pull --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/b: not pulled, since vendor/a above it wasn't fetched"* ]]
  [[ "$output" == *"Not fetched: vendor/a"* ]]
  [ "$(git log -1 --format=%s)" = "break vendor/a" ]
}

@test "nested: merge skips the splice below when the merge of the one above fails" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" "b change" main other.txt
  seed_bare_repo "$upstream" "a change"
  cd "$monorepo"
  splice fetch
  # A .splice at the root of a's upstream would replace vendor/a/.splice.
  seed_bare_repo "$upstream" "a root splice" main .splice
  splice fetch vendor/a
  run splice merge --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/b: not merged, since vendor/a above it failed"* ]]
  [[ "$output" == *"Failed: vendor/a vendor/a/b"* ]]
}

@test "nested: push goes bottom-up, and a failed push of the splice below stops the one above" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" "b upstream change" main other.txt
  cd "$monorepo"
  echo "b local" >>vendor/a/b/file.txt
  git commit -q -am "b local"
  run splice push --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/b:"*"vendor/a: not pushed, since vendor/a/b below it failed"* ]]
  [ "$(git -C "$upstream" log -1 --format=%s main)" != "b local" ]
}
