setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/05-nested-splices/01-nested-splices/setup'
  load 'scenarios/05-nested-splices/01-nested-splices/02-three-levels/setup'
  load 'scenarios/05-nested-splices/02-nested-default-branch/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/setup'
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

# In a's upstream, a maintainer changes b's file and pushes.
b_changed_in_upstream_a() {
  work_in_upstream_a
  echo "b in a's upstream" >>b/file.txt
  git -c user.name=Maintainer -c user.email=maintainer@example.com commit -q -am "b in a's upstream"
  git push -q origin HEAD:main
}

@test "nested: status shows a splice and the one below it" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  run splice status
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "  up to date  vendor/a" ]
  [ "${lines[2]}" = "  up to date  vendor/a/b" ]
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
  [ "${lines[*]:1}" = "  up to date  b" ]
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

@test "nested: b's history from before a's clone comes from a's upstream, so another monorepo's push of b isn't made again" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push vendor/a/b vendor/a
  local other="$BATS_TEST_TMPDIR/other"
  init_monorepo "$other"
  cd "$other"
  splice clone "$upstream" vendor/a
  splice fetch
  [ "$(rebuild_splice vendor/a/b)" = "$(git -C "$upstream_b" rev-parse main)" ]
}

@test "nested: a change to b made in a's upstream reaches b's upstream with its own author" {
  scenario_nested_splices "$monorepo" "$upstream"
  b_changed_in_upstream_a
  cd "$monorepo"
  splice pull vendor/a
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a/b)"
  [ "$(git log -1 --format='%s (%an)' "$rebuilt")" = "b in a's upstream (Maintainer)" ]
  [ "$(git rev-parse "$rebuilt^")" = "$(git -C "$upstream_b" rev-parse main)" ]
}

@test "nested: three levels deep, c's history from before a's clone comes from a's upstream, through b's" {
  scenario_three_levels "$monorepo" "$upstream"
  local upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  commit_local "$monorepo" vendor/a/b/c "c local"
  cd "$monorepo"
  splice push vendor/a/b/c vendor/a/b vendor/a
  local other="$BATS_TEST_TMPDIR/other"
  init_monorepo "$other"
  cd "$other"
  splice clone "$upstream" vendor/a
  splice fetch
  [ "$(rebuild_splice vendor/a/b/c)" = "$(git -C "$upstream_c" rev-parse main)" ]
}

@test "nested: b's history isn't taken from a's upstream once that has another splice at b/" {
  scenario_nested_splices "$monorepo" "$upstream"
  local upstream_b2="$BATS_TEST_TMPDIR/upstream-b2.git"
  make_bare_repo "$upstream_b2"
  seed_bare_repo "$upstream_b2" "b2 seed"
  work_in_upstream_a
  git rm -q -r b
  git commit -q -m "remove b"
  splice clone "$upstream_b2" b
  git push -q origin HEAD:main
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  run splice pull vendor/a
  [ "$status" -ne 0 ]
  git checkout HEAD -- vendor/a/b
  git commit -q --no-edit
  [ "$(splice_config vendor/a/b id)" != "$(git config --blob "$(splice_config vendor/a commit):b/.splice" splice.id)" ]
  run rebuild_splice vendor/a/b
  [ "$status" -eq 0 ]
  [ "$(git log --format=%s "$output")" = "b local"$'\n'"b seed" ]
  local rebuilt="$output"
  fetch_splice "$monorepo" "$upstream_b2"
  [ "$(rebuild_splice vendor/a/b)" = "$rebuilt" ]
}

@test "nested: b's push stays in b's history when a's upstream gets the same files from someone else" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push vendor/a/b
  work_in_upstream_a
  echo "b local" >>b/file.txt
  git -c user.name=Maintainer -c user.email=maintainer@example.com commit -q -am "the same change, made in a's upstream"
  echo "a change" >>file.txt
  git commit -q -am "a change"
  git push -q origin HEAD:main
  cd "$monorepo"
  splice pull vendor/a
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a/b)"
  git merge-base --is-ancestor "$(git -C "$upstream_b" rev-parse main)" "$rebuilt"
  commit_local "$monorepo" vendor/a/b "b next"
  splice fetch vendor/a/b
  run splice status vendor/a/b
  [[ "$output" != *behind* ]]
}

# Swaps the .splice files of vendor/a and vendor/a/b, ids and URLs
# included, in one commit.
swap_splice_files() {
  git mv vendor/a/.splice tmp.splice
  git mv vendor/a/b/.splice vendor/a/.splice
  git mv tmp.splice vendor/a/b/.splice
  git commit -q -m "swap the .splice files"
}

@test "nested: after a and b swap their .splice, each follows its id and keeps its own unpushed commits, nothing of the other's" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "a local" a.txt
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  local a_before b_before rebuilt
  a_before="$(rebuild_splice vendor/a)"
  b_before="$(rebuild_splice vendor/a/b)"
  swap_splice_files
  # vendor/a has b's id now, vendor/a/b a's.
  rebuilt="$(rebuild_splice vendor/a)"
  [ "$(git log -1 --format=%s "$rebuilt")" = "swap the .splice files" ]
  [ "$(git rev-parse "$rebuilt^")" = "$b_before" ]
  rebuilt="$(rebuild_splice vendor/a/b)"
  [ "$(git log -1 --format=%s "$rebuilt")" = "swap the .splice files" ]
  [ "$(git rev-parse "$rebuilt^")" = "$a_before" ]
}

@test "nested: after a and b swap their .splice, a pull of the folder below doesn't nest a in it again" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  swap_splice_files
  seed_bare_repo "$upstream" "a moves on"
  run splice pull vendor/a/b
  [ "$status" -ne 0 ]
  [ "$(git diff --name-only --diff-filter=U)" = "vendor/a/b/file.txt" ]
  [ -z "$(git ls-files vendor/a/b/b)" ]
}

@test "nested: b moved inside a keeps its unpushed commits" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  local before_move
  before_move="$(rebuild_splice vendor/a/b)"
  git mv vendor/a/b vendor/a/c
  git commit -q -m "rename b's folder"
  [ "$(rebuild_splice vendor/a/c)" = "$before_move" ]
  [ "$(git log -1 --format=%s "$before_move")" = "b local" ]
}

@test "nested: a change to b made in a's upstream keeps its author after b moves inside a" {
  scenario_nested_splices "$monorepo" "$upstream"
  b_changed_in_upstream_a
  cd "$monorepo"
  splice pull vendor/a
  local before_move
  before_move="$(rebuild_splice vendor/a/b)"
  git mv vendor/a/b vendor/a/c
  git commit -q -m "rename b's folder"
  [ "$(rebuild_splice vendor/a/c)" = "$before_move" ]
  [ "$(git log -1 --format='%s (%an)' "$before_move")" = "b in a's upstream (Maintainer)" ]
}

@test "nested: a change to b made in a's upstream keeps its author after a moves" {
  scenario_nested_splices "$monorepo" "$upstream"
  b_changed_in_upstream_a
  cd "$monorepo"
  splice pull vendor/a
  local before_move
  before_move="$(rebuild_splice vendor/a/b)"
  mkdir libs
  git mv vendor/a libs/a
  git commit -q -m "move a"
  [ "$(rebuild_splice libs/a/b)" = "$before_move" ]
  [ "$(git log -1 --format='%s (%an)' "$before_move")" = "b in a's upstream (Maintainer)" ]
}

@test "nested: after a moves, b's history from before a's clone still comes from a's upstream, so another monorepo's push of b isn't made again" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push vendor/a/b vendor/a
  local other="$BATS_TEST_TMPDIR/other"
  init_monorepo "$other"
  cd "$other"
  splice clone "$upstream" vendor/a
  splice fetch
  mkdir libs
  git mv vendor/a libs/a
  git commit -q -m "move a"
  [ "$(rebuild_splice libs/a/b)" = "$(git -C "$upstream_b" rev-parse main)" ]
}

@test "nested: a pull of a that moves b keeps b's unpushed commit, made before the move" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  work_in_upstream_a
  git mv b c
  git config --file c/.splice splice.default-branch main
  git commit -q -am "move b to c"
  git push -q origin HEAD:main
  cd "$monorepo"
  splice pull vendor/a
  grep -qx "b local" vendor/a/c/file.txt
  git log --format=%s "$(rebuild_splice vendor/a/c)" | grep -qx "b local"
}

@test "nested: a .splice below without default-branch follows the default branch of the splice above" {
  scenario_nested_default_branch "$monorepo" "$upstream"
  cd "$monorepo"
  splice clone "$upstream" vendor/a
  splice fetch
  run splice status
  [ "${lines[1]}" = "  up to date  vendor/a -> master" ]
  [ "${lines[2]}" = "  up to date  vendor/a/b -> master" ]
}

@test "nested: a .splice below without default-branch can't follow a splice above that pins a tag" {
  scenario_nested_default_branch "$monorepo" "$upstream"
  git -C "$upstream" tag v1 master
  cd "$monorepo"
  splice clone "$upstream" vendor/a
  git config --file vendor/a/.splice --unset upstream.origin.default-branch
  git config --file vendor/a/.splice upstream.origin.default-pin v1
  git commit -q -m "vendor/a: pin v1" -- vendor/a/.splice
  splice fetch vendor/a
  run splice status vendor/a/b
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a/b follows the default branch of vendor/a, which pins the tag 'v1' -- record one for vendor/a/b: git config --file vendor/a/b/.splice upstream.<name>.default-branch <branch>"* ]]
}

@test "nested: a .splice below with its own default-pin syncs with it inside a splice above that pins a tag" {
  scenario_nested_default_branch "$monorepo" "$upstream"
  git -C "$upstream" tag v1 master
  cd "$monorepo"
  splice clone "$upstream" vendor/a
  git config --file vendor/a/.splice --unset upstream.origin.default-branch
  git config --file vendor/a/.splice upstream.origin.default-pin v1
  local b_commit
  b_commit="$(git config --file vendor/a/b/.splice splice.commit)"
  git config --file vendor/a/b/.splice upstream.origin.default-pin "$b_commit"
  git commit -q -m "pin vendor/a and vendor/a/b" -- vendor/a/.splice vendor/a/b/.splice
  splice fetch
  run splice status vendor/a/b
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "  up to date  vendor/a/b -> ${b_commit:0:7}" ]
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
  [ -z "$(upstream_config vendor/a/c origin default-branch)" ]
  [ "$(upstream_config vendor/a/d origin default-branch)" = main ]
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

@test "nested: clone inside a splice refuses an upstream without the splice above's default branch and with no default branch, instead of trying the monorepo's branch name" {
  scenario_nested_default_branch "$monorepo" "$upstream"
  local no_head="$BATS_TEST_TMPDIR/no-head.git"
  make_bare_repo "$no_head" main
  seed_bare_repo "$no_head" "main seed" main
  # HEAD names a branch that doesn't exist, so it isn't advertised.
  git -C "$no_head" symbolic-ref HEAD refs/heads/gone
  cd "$monorepo"
  splice clone "$upstream" vendor/a
  run cmd_clone "$no_head" vendor/a/f
  [ "$status" -eq 1 ]
  [[ "$output" == *"upstream has no 'master' branch and names no default branch"* ]]
  [ ! -e vendor/a/f/.splice ]
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
  [ -z "$(upstream_config vendor/a/e origin default-branch)" ]
  [ "$(upstream_branch_for vendor/a/e main)" = master ]
}

@test "nested: cloning an upstream that contains a .splice makes its folder a splice" {
  scenario_nested_splices "$BATS_TEST_TMPDIR/first" "$upstream"
  init_monorepo "$monorepo"
  cd "$monorepo"
  splice clone "$upstream" lib
  [ "$(git show HEAD:lib/b/.splice)" = "$(git -C "$upstream" show main:b/.splice)" ]
  run splice status
  [ "${lines[1]}" = "  ?? never fetched  lib/b  run 'git splice fetch lib/b'" ]
  [ "${lines[2]}" = "  up to date        lib" ]
}

@test "nested: a merge brings in a .splice the upstream added, and the folder becomes a splice" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "$(printf '[splice]\n\tid = 0123456789abcdef\n[upstream "origin"]\n\turl = %s' "$upstream")" main extra/.splice
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
  [ "${lines[*]:1}" = "  ahead 2  vendor/a/b" ]
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
  [ "${lines[1]}" = "  up to date  vendor/a" ]
  [ "${lines[2]}" = "  up to date  vendor/a/b" ]
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

# a's upstream pulls "b change" into b/, then b's upstream drops it from
# main: the synced commit a's upstream records for b is on no branch.
b_moved_to_a_commit_no_branch_has() {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" "b change" main other.txt
  work_in_upstream_a
  splice pull b >/dev/null
  git push -q origin main
  git -C "$upstream_b" update-ref refs/heads/main refs/heads/main^
  cd "$monorepo"
}

@test "nested: pull --all fetches the synced commit the pull of a moves b to, though no branch of b's upstream has it" {
  b_moved_to_a_commit_no_branch_has
  run splice pull --all
  [ "$status" -eq 0 ]
  [ "$(git show HEAD:vendor/a/b/other.txt)" = "b change" ]
}

@test "nested: pull of a alone fetches the synced commit it moves b to, though no branch of b's upstream has it" {
  b_moved_to_a_commit_no_branch_has
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  synced="$(splice_config vendor/a/b commit)"
  git cat-file -e "$synced^{commit}"
  run splice status vendor/a/b
  [[ "$output" != *"no common"* && "$output" != *"unrelated"* ]]
}

@test "nested: pull --all fetches the tag the pull of a pins b at" {
  scenario_nested_splices "$monorepo" "$upstream"
  git -C "$upstream_b" tag v1 main
  work_in_upstream_a
  git config --file b/.splice upstream.origin.default-pin v1
  git commit -q -m "pin b at v1" -- b/.splice
  git push -q origin main
  cd "$monorepo"
  run splice pull --all
  [ "$status" -eq 0 ]
  run splice status vendor/a/b
  [ "${lines[1]}" = "  up to date  vendor/a/b -> tags/v1" ]
}

# As above, and b's upstream lost the dropped commit for good, e.g. to gc.
b_moved_to_a_commit_upstream_lost() {
  b_moved_to_a_commit_no_branch_has
  git -C "$upstream_b" reflog expire --expire=now --all
  git -C "$upstream_b" gc -q --prune=now
  synced_after="$(git -C "$upstream" show main:b/.splice | git config --file - splice.commit)"
}

@test "nested: pull of a says so when the synced commit it moves b to is gone from b's upstream" {
  b_moved_to_a_commit_upstream_lost
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a/b: its synced commit ${synced_after:0:7}, from a pull above, isn't on its upstream any more"* ]]
}

@test "nested: pull --all says so when the synced commit a moves b to is gone from b's upstream, rather than that b shares no history" {
  b_moved_to_a_commit_upstream_lost
  run splice pull --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a/b: its synced commit ${synced_after:0:7}, from a pull above, isn't on its upstream any more"* ]]
  [[ "$output" != *"no common"* ]]
}

@test "nested: merge --all says b's synced commit, from the merge of a, isn't fetched yet, rather than that b shares no history" {
  b_moved_to_a_commit_no_branch_has
  splice fetch >/dev/null
  run splice merge --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"??   vendor/a/b: not fetched yet -- run 'git splice fetch vendor/a/b' first"* ]]
  run splice pull vendor/a/b
  [ "$status" -eq 0 ]
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

@test "nested: a splice goes below the nearest splice given above it, also across folders that aren't splices, and a path given twice comes once" {
  run splices_in_order top-down a/b/c/d x a/b a/b/c/d a
  [ "$output" = $'a\na/b\na/b/c/d\nx' ]
  run splices_in_order bottom-up a/b/c/d x a/b a/b/c/d a
  [ "$output" = $'a/b/c/d\na/b\na\nx' ]
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
