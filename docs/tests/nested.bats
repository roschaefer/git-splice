setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load '../09-scenarios/05-nested-splices/01-nested-splices/setup'
  load '../09-scenarios/05-nested-splices/01-nested-splices/02-three-levels/setup'
  load '../09-scenarios/05-nested-splices/02-nested-default-branch/setup'
  load '../09-scenarios/01-everyday-sync/02-up-to-date/setup'
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

@test "nested: push of the splice above sends the files of the one below, and its .splice recording the one below at its rebuild" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push vendor/a
  [ "$(git -C "$upstream" ls-tree -r --name-only main)" = $'b/.splice\nb/file.txt\nfile.txt' ]
  [ "$(git -C "$upstream" rev-parse main:b/file.txt)" = "$(git rev-parse HEAD:vendor/a/b/file.txt)" ]
  [ "$(git -C "$upstream" show main:b/.splice | git config --file - splice.commit)" = "$(splice rebuild vendor/a/b)" ]
  [ "$(splice_config vendor/a/b commit)" != "$(splice rebuild vendor/a/b)" ]
}

@test "nested: one push --all leaves the upstream above recording what the one below has" {
  scenario_three_levels "$monorepo" "$upstream"
  local upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  commit_local "$monorepo" vendor/a/b/c "c local"
  cd "$monorepo"
  splice push --all
  [ "$(git -C "$upstream_b" show main:c/.splice | git config --file - splice.commit)" = "$(git -C "$upstream_c" rev-parse main)" ]
  [ "$(git -C "$upstream" show main:b/.splice | git config --file - splice.commit)" = "$(git -C "$upstream_b" rev-parse main)" ]
  [ "$(git -C "$upstream" show main:b/c/.splice | git config --file - splice.commit)" = "$(git -C "$upstream_c" rev-parse main)" ]
  [ -z "$(git status --porcelain)" ]
}

@test "nested: a pull of the splice above, after its upstream pulled the one below further, doesn't conflict in the record the monorepo's push wrote" {
  scenario_three_levels "$monorepo" "$upstream"
  local upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  commit_local "$monorepo" vendor/a/b/c "c local"
  cd "$monorepo"
  splice push --all >/dev/null
  seed_bare_repo "$upstream_c" "c upstream" main other.txt
  local b_work="$BATS_TEST_TMPDIR/b-work"
  git clone -q "$upstream_b" "$b_work"
  (cd "$b_work" && git config user.name Test && git config user.email test@example.com &&
    splice pull c >/dev/null && git push -q origin main)
  run splice pull vendor/a/b
  [ "$status" -eq 0 ]
  [[ "$output" != *CONFLICT* ]]
  [ "$(splice_config vendor/a/b/c commit)" = "$(git -C "$upstream_c" rev-parse main)" ]
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
  [ "$(splice rebuild vendor/a/b)" = "$(git -C "$upstream_b" rev-parse main)" ]
}

@test "nested: a change to b made in a's upstream reaches b's upstream with its own author" {
  scenario_nested_splices "$monorepo" "$upstream"
  b_changed_in_upstream_a
  cd "$monorepo"
  splice pull vendor/a
  local rebuilt
  rebuilt="$(splice rebuild vendor/a/b)"
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
  [ "$(splice rebuild vendor/a/b/c)" = "$(git -C "$upstream_c" rev-parse main)" ]
}

@test "nested: c's own new synced commit wins over b's upstream when one commit moves both" {
  scenario_three_levels "$monorepo" "$upstream"
  local upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  seed_bare_repo "$upstream_b" "b upstream"
  seed_bare_repo "$upstream_c" "c upstream"
  cd "$monorepo"
  splice pull vendor/a/b
  splice pull vendor/a/b/c
  git reset -q --soft HEAD~2
  git commit -q -m "pull b and c"
  [ "$(splice rebuild vendor/a/b/c)" = "$(git -C "$upstream_c" rev-parse main)" ]
  run splice status
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date  vendor/a/b/c"* ]]
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
  run splice rebuild vendor/a/b
  [ "$status" -eq 0 ]
  [ "$(git log --format=%s "$output")" = "b local"$'\n'"b seed" ]
  local rebuilt="$output"
  fetch_splice "$monorepo" "$upstream_b2"
  [ "$(splice rebuild vendor/a/b)" = "$rebuilt" ]
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
  rebuilt="$(splice rebuild vendor/a/b)"
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
  a_before="$(splice rebuild vendor/a)"
  b_before="$(splice rebuild vendor/a/b)"
  swap_splice_files
  # vendor/a has b's id now, vendor/a/b a's.
  rebuilt="$(splice rebuild vendor/a)"
  [ "$(git log -1 --format=%s "$rebuilt")" = "swap the .splice files" ]
  [ "$(git rev-parse "$rebuilt^")" = "$b_before" ]
  rebuilt="$(splice rebuild vendor/a/b)"
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
  before_move="$(splice rebuild vendor/a/b)"
  git mv vendor/a/b vendor/a/c
  git commit -q -m "rename b's folder"
  [ "$(splice rebuild vendor/a/c)" = "$before_move" ]
  [ "$(git log -1 --format=%s "$before_move")" = "b local" ]
}

@test "nested: a change to b made in a's upstream keeps its author after b moves inside a" {
  scenario_nested_splices "$monorepo" "$upstream"
  b_changed_in_upstream_a
  cd "$monorepo"
  splice pull vendor/a
  local before_move
  before_move="$(splice rebuild vendor/a/b)"
  git mv vendor/a/b vendor/a/c
  git commit -q -m "rename b's folder"
  [ "$(splice rebuild vendor/a/c)" = "$before_move" ]
  [ "$(git log -1 --format='%s (%an)' "$before_move")" = "b in a's upstream (Maintainer)" ]
}

@test "nested: a change to b made in a's upstream keeps its author after a moves" {
  scenario_nested_splices "$monorepo" "$upstream"
  b_changed_in_upstream_a
  cd "$monorepo"
  splice pull vendor/a
  local before_move
  before_move="$(splice rebuild vendor/a/b)"
  mkdir libs
  git mv vendor/a libs/a
  git commit -q -m "move a"
  [ "$(splice rebuild libs/a/b)" = "$before_move" ]
  [ "$(git log -1 --format='%s (%an)' "$before_move")" = "b in a's upstream (Maintainer)" ]
}

@test "nested: a change to b made in a's upstream keeps its author when a pull of a brings it after a moved" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir libs
  git mv vendor/a libs/a
  git commit -q -m "move a"
  b_changed_in_upstream_a
  cd "$monorepo"
  splice pull libs/a
  local rebuilt
  rebuilt="$(splice rebuild libs/a/b)"
  [ "$(git log -1 --format='%s (%an)' "$rebuilt")" = "b in a's upstream (Maintainer)" ]
  [ "$(git rev-parse "$rebuilt^")" = "$(git -C "$upstream_b" rev-parse main)" ]
}

@test "nested: b's unpushed commit from before a moved is kept when a pull of a after the move brings a change to b" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local" local.txt
  cd "$monorepo"
  mkdir libs
  git mv vendor/a libs/a
  git commit -q -m "move a"
  b_changed_in_upstream_a
  cd "$monorepo"
  splice pull libs/a
  local rebuilt
  rebuilt="$(splice rebuild libs/a/b)"
  git log --format='%s (%an)' "$rebuilt" | grep -qx "b local (Test)"
  git log --format='%s (%an)' "$rebuilt" | grep -qx "b in a's upstream (Maintainer)"
  [ "$(git rev-parse "$rebuilt:local.txt")" = "$(git rev-parse HEAD:libs/a/b/local.txt)" ]
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
  [ "$(splice rebuild libs/a/b)" = "$(git -C "$upstream_b" rev-parse main)" ]
}

@test "nested: a pull of a that moves b keeps b's unpushed commit, made before the move" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  work_in_upstream_a
  git mv b c
  git config --file c/.splice upstream.origin.default-branch main
  git commit -q -am "move b to c"
  git push -q origin HEAD:main
  cd "$monorepo"
  splice pull vendor/a
  grep -qx "b local" vendor/a/c/file.txt
  git log --format=%s "$(splice rebuild vendor/a/c)" | grep -qx "b local"
}

@test "nested: a pull of a that moves b without changing its .splice keeps b's unpushed commit, made before the move" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  work_in_upstream_a
  git mv b c
  git commit -q -m "move b to c"
  git push -q origin HEAD:main
  cd "$monorepo"
  splice pull vendor/a
  grep -qx "b local" vendor/a/c/file.txt
  git log --format=%s "$(splice rebuild vendor/a/c)" | grep -qx "b local"
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
  splice clone "$upstream_b" vendor/a/c
  splice clone "$upstream_main" vendor/a/d
  [ -z "$(upstream_config vendor/a/c origin default-branch)" ]
  [ "$(upstream_config vendor/a/d origin default-branch)" = main ]
  [[ "$(splice status vendor/a/c)" == *"vendor/a/c -> master"* ]]
  [[ "$(splice status vendor/a/d)" != *"->"* ]]
}

@test "nested: clone inside a splice refuses when the monorepo's default branch can't be determined, though the splice above's can" {
  scenario_nested_default_branch "$monorepo" "$upstream"
  cd "$monorepo"
  splice clone "$upstream" vendor/a
  git config --unset init.defaultBranch
  run splice clone "$upstream_b" vendor/a/c
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
  run splice clone "$no_head" vendor/a/f
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
  run splice init vendor/a/e "$empty_master"
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
  splice init vendor/a/e "$empty_master"
  [ -z "$(upstream_config vendor/a/e origin default-branch)" ]
  [[ "$(splice status vendor/a/e)" == *"vendor/a/e -> master"* ]]
}

@test "nested: cloning an upstream that contains a .splice makes its folder a splice, fetched too" {
  scenario_nested_splices "$BATS_TEST_TMPDIR/first" "$upstream"
  init_monorepo "$monorepo"
  cd "$monorepo"
  splice clone "$upstream" lib
  [ "$(git show HEAD:lib/b/.splice)" = "$(git -C "$upstream" show main:b/.splice)" ]
  run splice status
  [ "${lines[1]}" = "  up to date  lib" ]
  [ "${lines[2]}" = "  up to date  lib/b" ]
}

@test "nested: a merge brings in a .splice the upstream added, and the folder becomes a splice" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "$(printf '[splice]\n\tid = 0123456789abcdef\n[upstream "origin"]\n\turl = %s' "$upstream")" main extra/.splice
  cd "$monorepo"
  splice pull vendor/a
  [ "$(discovered_splices)" = "vendor/a vendor/a/extra" ]
}

@test "nested: clone and init make a splice inside an existing one" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  splice clone "$upstream_b" vendor/a/c
  mkdir vendor/a/d && echo d >vendor/a/d/file.txt
  git add vendor/a/d && git commit -q -m "add d"
  make_bare_repo "$BATS_TEST_TMPDIR/d.git"
  splice init vendor/a/d "$BATS_TEST_TMPDIR/d.git"
  [ "$(discovered_splices)" = "vendor/a vendor/a/b vendor/a/c vendor/a/d" ]
}

@test "nested: init makes a splice around an existing one" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  make_bare_repo "$BATS_TEST_TMPDIR/vendor.git"
  splice init vendor "$BATS_TEST_TMPDIR/vendor.git"
  splice push vendor
  [ "$(git -C "$BATS_TEST_TMPDIR/vendor.git" ls-tree -r --name-only main)" = $'a/.splice\na/b/.splice\na/b/file.txt\na/file.txt' ]
}

@test "nested: init around a splice records the default branch it followed in its .splice, where the new splice's differs, and the ones below keep theirs" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  git init -q --bare -b master "$BATS_TEST_TMPDIR/vendor.git"
  run splice init vendor "$BATS_TEST_TMPDIR/vendor.git"
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: records default-branch 'main' for origin, which it followed before"* ]]
  [ "$(git config --file vendor/.splice upstream.origin.default-branch)" = "master" ]
  [ "$(git config --file vendor/a/.splice upstream.origin.default-branch)" = "main" ]
  [ -z "$(git config --file vendor/a/b/.splice upstream.origin.default-branch)" ]
  [ "$(git show --name-only --format= HEAD)" = $'vendor/.splice\nvendor/a/.splice' ]
  run splice status vendor/a vendor/a/b
  [[ "$output" == *"up to date  vendor/a"* ]]
  [[ "$output" == *"up to date  vendor/a/b"* ]]
}

@test "nested: init around a splice records nothing in its .splice when the new splice's default branch is the one it followed" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  git init -q --bare -b main "$BATS_TEST_TMPDIR/vendor.git"
  run splice init vendor "$BATS_TEST_TMPDIR/vendor.git"
  [ "$status" -eq 0 ]
  [[ "$output" != *"records default-branch"* ]]
  [ "$(git show --name-only --format= HEAD)" = "vendor/.splice" ]
}

@test "nested: init around a splice leaves a default-branch it records already" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.origin.default-branch main
  git commit -q -am "a: on main"
  git init -q --bare -b master "$BATS_TEST_TMPDIR/vendor.git"
  run splice init vendor "$BATS_TEST_TMPDIR/vendor.git"
  [ "$status" -eq 0 ]
  [[ "$output" != *"records default-branch"* ]]
  [ "$(git show --name-only --format= HEAD)" = "vendor/.splice" ]
}

@test "nested: init around a splice refuses, keeping the edit, when the .splice it would record the default branch in has uncommitted changes" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  echo "# a comment" >>vendor/a/.splice
  git init -q --bare -b master "$BATS_TEST_TMPDIR/vendor.git"
  head=$(git rev-parse HEAD)
  run splice init vendor "$BATS_TEST_TMPDIR/vendor.git"
  [ "$status" -ne 0 ]
  [[ "$output" == *"vendor/a/.splice"*"vendor: init failed"* ]]
  [ "$(git rev-parse HEAD)" = "$head" ]
  [ ! -e vendor/.splice ]
  [ "$(tail -n 1 vendor/a/.splice)" = "# a comment" ]
}

@test "nested: init around a splice refuses when the .splice it would record the default branch in has staged changes its working tree undid" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  echo "# a comment" >>vendor/a/.splice
  git add vendor/a/.splice
  git show HEAD:vendor/a/.splice >vendor/a/.splice
  git init -q --bare -b master "$BATS_TEST_TMPDIR/vendor.git"
  run splice init vendor "$BATS_TEST_TMPDIR/vendor.git"
  [ "$status" -ne 0 ]
  [[ "$output" == *"vendor/a/.splice"*"vendor: init failed"* ]]
  [[ "$(git show :vendor/a/.splice)" == *"# a comment" ]]
}

@test "nested: init around a splice refuses when the .splice it would record the default branch in has changes hidden by assume-unchanged" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  git update-index --assume-unchanged vendor/a/.splice
  echo "# a comment" >>vendor/a/.splice
  git init -q --bare -b master "$BATS_TEST_TMPDIR/vendor.git"
  run splice init vendor "$BATS_TEST_TMPDIR/vendor.git"
  [ "$status" -ne 0 ]
  [[ "$output" == *"vendor/a/.splice"*"vendor: init failed"* ]]
  [ "$(tail -n 1 vendor/a/.splice)" = "# a comment" ]
}

@test "nested: init around a splice writes the .splice it records the default branch in with its checkout attributes" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  echo "/.splice working-tree-encoding=UTF-16LE" >vendor/a/.gitattributes
  git add vendor/a/.gitattributes
  rm vendor/a/.splice
  git checkout -- vendor/a/.splice
  git commit -q -m "a: .splice in UTF-16LE"
  git init -q --bare -b master "$BATS_TEST_TMPDIR/vendor.git"
  run splice init vendor "$BATS_TEST_TMPDIR/vendor.git"
  [ "$status" -eq 0 ]
  [ -z "$(git status --porcelain)" ]
  [ "$(git config --file <(iconv -f UTF-16LE -t UTF-8 vendor/a/.splice) upstream.origin.default-branch)" = "main" ]
}

@test "nested: init around a splice leaves other staged changes staged and out of its commit" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  echo staged >vendor/a/file.txt
  git add vendor/a/file.txt
  git init -q --bare -b master "$BATS_TEST_TMPDIR/vendor.git"
  run splice init vendor "$BATS_TEST_TMPDIR/vendor.git"
  [ "$status" -eq 0 ]
  [ "$(git show --name-only --format= HEAD)" = $'vendor/.splice\nvendor/a/.splice' ]
  [ "$(git diff --cached --name-only)" = "vendor/a/file.txt" ]
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

@test "nested: pull --all says the pull of a removed b" {
  scenario_nested_splices "$monorepo" "$upstream"
  work_in_upstream_a
  git rm -q b/.splice
  git commit -q -m "b is part of a"
  git push -q origin main
  cd "$monorepo"
  run splice pull --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a/b: removed by the pull of vendor/a"* ]]
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
  run splice pull --recursive vendor/a
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

@test "nested: pull of a fetches the synced commit it moves b to from b's upstream, also when it adds a second upstream to b that lacks it" {
  b_moved_to_a_commit_no_branch_has
  upstream_fork="$BATS_TEST_TMPDIR/upstream-fork.git"
  git clone -q --bare --no-local "$upstream_b" "$upstream_fork"
  cd "$a_work"
  git config --file b/.splice upstream.fork.url "$upstream_fork"
  git commit -q -m "b: a fork" -- b/.splice
  git push -q origin main
  cd "$monorepo"
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  synced="$(splice_config vendor/a/b commit)"
  git cat-file -e "$synced^{commit}"
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

# Adds splices at paths $@ of the same upstream.
add_splices_at() {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  local path
  for path in "$@"; do
    add_splice "$monorepo" "$upstream" "$path"
  done
  cd "$monorepo"
}

# Prints the path of each line of `git splice <command> <paths>`'s report,
# in order. The command may fail: a push reports the splices it refuses too.
order_of() {
  local output
  output="$(splice "$@" 2>&1)" || true
  grep -v 'Failed:' <<<"$output" | sed -nE 's/^(ok|!!|\?\?) +([^ :]+).*/\2/p' | paste -sd ' ' -
}

@test "nested: top-down puts each splice after the ones above it, bottom-up before them, and keeps the order given otherwise" {
  add_splices_at deep/x deep/x/y other z
  [ "$(order_of merge --all)" = "deep/x deep/x/y other z" ]
  [ "$(order_of push deep/x/y other deep/x z)" = "deep/x/y deep/x other z" ]
}

@test "nested: subtrees under the same splice keep the order of their first path too" {
  add_splices_at a a/b a/b/d a/c
  [ "$(order_of merge --all)" = "a a/b a/b/d a/c" ]
  [ "$(order_of push a/b/d a/c a/b a)" = "a/b/d a/b a/c a" ]
}

@test "nested: a splice goes below the nearest splice given above it, also across folders that aren't splices, and a path given twice comes once" {
  add_splices_at a a/b a/b/c/d x
  [ "$(order_of merge --all)" = "a a/b a/b/c/d x" ]
  [ "$(order_of push a/b/c/d x a/b a/b/c/d a)" = "a/b/c/d a/b a x" ]
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

@test "nested: pull of a fetches b from the URL a's pull brings in, not from the one b had before" {
  scenario_nested_splices "$monorepo" "$upstream"
  upstream_b2="$BATS_TEST_TMPDIR/upstream-b2.git"
  git clone -q --bare "$upstream_b" "$upstream_b2"
  seed_bare_repo "$upstream_b2" "b moved" main other.txt
  work_in_upstream_a
  git config --file b/.splice upstream.origin.url "$upstream_b2"
  git commit -q -m "b moved" -- b/.splice
  git push -q origin main
  cd "$monorepo"
  splice pull vendor/a
  [ "$(splice_state vendor/a/b)" = "pull" ]
}

@test "nested: pull --recursive of a follows the default branch b's new .splice names, after a's pull renames b's upstream" {
  scenario_three_levels "$monorepo" "$upstream"
  upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  seed_bare_repo "$upstream_c" "c dev" dev other.txt
  work_in_upstream_a
  git config --file b/.splice --rename-section upstream.origin upstream.fork
  git config --file b/.splice upstream.fork.default-branch dev
  git commit -q -m "b: fork, on dev" -- b/.splice
  git push -q origin main
  cd "$monorepo"
  splice pull --recursive vendor/a
  [ "$(git show HEAD:vendor/a/b/c/other.txt)" = "c dev" ]
}

@test "nested: b pushed from a clone of a's upstream, after a push of a alone, is up to date in the monorepo" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push vendor/a
  work_in_upstream_a
  splice fetch b
  splice push b
  cd "$monorepo"
  splice fetch vendor/a/b
  [ "$(splice_state vendor/a/b)" = "up-to-date" ]
}

@test "nested: a pull of b that conflicts leaves the conflict in the monorepo's working tree, at b's file" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" "b upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  run splice pull vendor/a/b
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/b: conflict -- resolve it, then 'git commit'"* ]]
  [ "$(git diff --name-only --diff-filter=U)" = "vendor/a/b/file.txt" ]
}

@test "nested: pull --recursive of a doesn't merge b from an upstream fetched before, when a's pull names it and fetching it fails" {
  scenario_nested_splices "$monorepo" "$upstream"
  upstream_b2="$BATS_TEST_TMPDIR/upstream-b2.git"
  git clone -q --bare "$upstream_b" "$upstream_b2"
  seed_bare_repo "$upstream_b2" "b moved" main other.txt
  work_in_upstream_a
  git config --file b/.splice upstream.origin.url "$upstream_b2"
  git commit -q -m "b moved" -- b/.splice
  git push -q origin main
  cd "$monorepo"
  splice pull vendor/a
  cd "$a_work"
  git revert --no-edit HEAD >/dev/null
  git push -q origin main
  cd "$monorepo"
  splice pull vendor/a
  cd "$a_work"
  git revert --no-edit HEAD >/dev/null
  git push -q origin main
  mv "$upstream_b2" "$upstream_b2.gone"
  cd "$monorepo"
  run splice pull --recursive vendor/a
  [ "$status" -ne 0 ]
  [[ "$output" == *"vendor/a/b fetch failed"*"vendor/a: not pulled, since vendor/a/b below it wasn't fetched"* ]]
  [[ "$output" == *"Not fetched: vendor/a/b"* ]]
  ! git cat-file -e HEAD:vendor/a/b/other.txt
}

@test "nested: pull --all skips a, b and c when c's upstream from a's pull fails to fetch, though b's pull would name one that fetches" {
  scenario_three_levels "$monorepo" "$upstream"
  upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  upstream_c2="$BATS_TEST_TMPDIR/upstream-c2.git"
  git clone -q --bare "$upstream_c" "$upstream_c2"
  b_work="$BATS_TEST_TMPDIR/b-work"
  git clone -q "$upstream_b" "$b_work"
  cd "$b_work"
  git config user.name "Test"
  git config user.email "test@example.com"
  git config --file c/.splice upstream.origin.url "$upstream_c2"
  git commit -q -m "c moved" -- c/.splice
  git push -q origin main
  work_in_upstream_a
  splice pull b
  git push -q origin main
  cd "$b_work"
  git revert --no-edit HEAD >/dev/null
  git push -q origin main
  mv "$upstream_c2" "$upstream_c2.gone"
  seed_bare_repo "$upstream_c" "c change" main other.txt
  cd "$monorepo"
  head=$(git rev-parse HEAD)
  run splice pull --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"vendor/a: not pulled, since vendor/a/b/c below it wasn't fetched"* ]]
  [[ "$output" == *"vendor/a/b: not pulled, since vendor/a/b/c below it wasn't fetched"* ]]
  [[ "$output" == *"Not fetched: vendor/a/b/c"* ]]
  [ "$(git rev-parse HEAD)" = "$head" ]
}

@test "nested: pull of a fetches every upstream of b when a's pull gives b a second one and no default, as b isn't merged" {
  scenario_nested_splices "$monorepo" "$upstream"
  upstream_fork="$BATS_TEST_TMPDIR/upstream-fork.git"
  git clone -q --bare "$upstream_b" "$upstream_fork"
  work_in_upstream_a
  git config --file b/.splice upstream.fork.url "$upstream_fork"
  git commit -q -m "b: a fork" -- b/.splice
  git push -q origin main
  cd "$monorepo"
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  git cat-file -e HEAD:vendor/a/b/.splice
  [ "$(git config --file vendor/a/b/.splice upstream.fork.url)" = "$upstream_fork" ]
  key="$(splice key --upstream fork vendor/a/b)"
  [ "$(git rev-parse "refs/splices/$key/heads/main")" = "$(git -C "$upstream_fork" rev-parse main)" ]
}

@test "nested: pull of a and x skips a when a's pull would bring a .splice for b that can't be loaded, and pulls x" {
  scenario_nested_splices "$monorepo" "$upstream"
  upstream_x="$BATS_TEST_TMPDIR/upstream-x.git"
  make_bare_repo "$upstream_x"
  seed_bare_repo "$upstream_x" "x seed"
  add_splice "$monorepo" "$upstream_x" vendor/x
  seed_bare_repo "$upstream_x" "x change" main other.txt
  work_in_upstream_a
  git config --file b/.splice --unset upstream.origin.url
  git commit -q -m "b: no URL" -- b/.splice
  git push -q origin main
  cd "$monorepo"
  run splice pull vendor/a vendor/x
  [ "$status" -ne 0 ]
  [[ "$output" == *"vendor/a: not pulled, since vendor/a/b below it wasn't fetched"* ]]
  [[ "$output" == *"vendor/x: pulled"* ]]
  [[ "$output" == *"Not fetched: vendor/a/b"* ]]
}

@test "nested: a pull of b made in a worktree of a's rebuild, merged back with merge --rebuilt-commit, is a pull of b in the monorepo" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" "b upstream" main other.txt
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice fetch vendor/a vendor/a/b
  git worktree add -q -b layer "$BATS_TEST_TMPDIR/layer" "$(splice rebuild vendor/a)"
  (cd "$BATS_TEST_TMPDIR/layer" && splice pull --branch main b)
  run splice merge --rebuilt-commit layer vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "splice: pull b from main at $(git -C "$upstream_b" rev-parse --short main)" ]
  [ "$(splice_config vendor/a/b commit)" = "$(git -C "$upstream_b" rev-parse main)" ]
  [ "$(splice_state vendor/a/b)" = "push" ]
  splice push vendor/a/b
  [ "$(git -C "$upstream_b" log --format=%s -1 main^2)" = "b upstream" ]
}

@test "nested: pull --recursive pulls the splices below too, the one above first" {
  scenario_three_levels "$monorepo" "$upstream"
  local upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  seed_bare_repo "$upstream_b" "b upstream"
  seed_bare_repo "$upstream_c" "c upstream"
  cd "$monorepo"
  run splice pull --recursive vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: nothing to pull"* ]]
  [ "$(git log -1 --format=%s)" = "splice: pull vendor/a and the splices in it" ]
  [[ "$(git log -1 --format=%b)" == "splice: pull vendor/a/b from main at "*$'\n'"splice: pull vendor/a/b/c from main at "* ]]
  [ "$(git log -1 --format=%s HEAD~1)" = "add vendor/a" ]
  run splice status
  [[ "$output" == *"up to date  vendor/a/b/c"* ]]
}

@test "nested: pull without --recursive leaves the splices below alone" {
  scenario_three_levels "$monorepo" "$upstream"
  local upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  seed_bare_repo "$upstream_c" "c upstream"
  cd "$monorepo"
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "add vendor/a" ]
}

@test "nested: pull --recursive also pulls a splice the pull above adds" {
  scenario_nested_splices "$monorepo" "$upstream"
  local upstream_e="$BATS_TEST_TMPDIR/upstream-e.git"
  make_bare_repo "$upstream_e"
  seed_bare_repo "$upstream_e" "e seed"
  work_in_upstream_a
  splice clone "$upstream_e" e
  git push -q origin HEAD:main
  seed_bare_repo "$upstream_e" "e upstream"
  cd "$monorepo"
  run splice pull --recursive vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a/e fetched"*"vendor/a/e: pulled"* ]]
  [ "$(cat vendor/a/e/file.txt)" = "e seed"$'\n'"e upstream" ]
}

@test "nested: pull --recursive run again after a conflict pulls the splices it didn't get to" {
  scenario_three_levels "$monorepo" "$upstream"
  local upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  commit_local "$monorepo" vendor/a/b "b local"
  seed_bare_repo "$upstream_b" "b upstream"
  seed_bare_repo "$upstream_c" "c upstream"
  cd "$monorepo"
  run splice pull --recursive vendor/a
  [ "$status" -ne 0 ]
  [[ "$output" == *"Not pulled yet: vendor/a/b/c"* ]]
  echo resolved >vendor/a/b/file.txt
  git add vendor/a/b/file.txt
  git commit -q --no-edit
  run splice pull --recursive vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a/b: nothing to pull"*"vendor/a/b/c: pulled"* ]]
}

@test "nested: pull --recursive makes one commit of the pulls of all its runs" {
  scenario_three_levels "$monorepo" "$upstream"
  local upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  commit_local "$monorepo" vendor/a/b "b local"
  seed_bare_repo "$upstream_b" "b upstream"
  seed_bare_repo "$upstream_c" "c upstream"
  cd "$monorepo"
  run splice pull --recursive vendor/a
  [ "$status" -ne 0 ]
  echo resolved >vendor/a/b/file.txt
  git add vendor/a/b/file.txt
  git commit -q --no-edit
  run splice pull --recursive vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 pulls made one commit"* ]]
  [ "$(git log -2 --format=%s)" = "splice: pull vendor/a and the splices in it"$'\n'"b local" ]
  [ "$(splice rebuild vendor/a/b/c)" = "$(git -C "$upstream_c" rev-parse main)" ]
  ! git rev-parse --quiet --verify SPLICE_PULL_START
}

@test "nested: pull --recursive leaves its pulls separate when another commit came in between" {
  scenario_three_levels "$monorepo" "$upstream"
  local upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  commit_local "$monorepo" vendor/a/b "b local"
  seed_bare_repo "$upstream_b" "b upstream"
  seed_bare_repo "$upstream_c" "c upstream"
  cd "$monorepo"
  run splice pull --recursive vendor/a
  [ "$status" -ne 0 ]
  echo resolved >vendor/a/b/file.txt
  git add vendor/a/b/file.txt
  git commit -q --no-edit
  echo other >other.txt
  git add other.txt
  git commit -q -m "something else"
  run splice pull --recursive vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"isn't a pull -- the pulls since the recursive pull started stay separate commits"* ]]
  [[ "$(git log -1 --format=%s)" == "splice: pull vendor/a/b/c from main at "* ]]
  ! git rev-parse --quiet --verify SPLICE_PULL_START
}

@test "nested: pull --recursive says which pull removed a splice below" {
  scenario_three_levels "$monorepo" "$upstream"
  work_in_upstream_a
  git rm -q -r b
  git commit -q -m "drop b"
  git push -q origin HEAD:main
  cd "$monorepo"
  run splice pull --recursive vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a/b: removed by the pull of vendor/a"* ]]
  [[ "$output" == *"vendor/a/b/c: removed by the pull of vendor/a"* ]]
}

@test "nested: pull --recursive starts again after the branch was reset past where an aborted run started" {
  scenario_three_levels "$monorepo" "$upstream"
  local upstream_c="$BATS_TEST_TMPDIR/upstream-c.git" dropped
  commit_local "$monorepo" vendor/a/b "b local"
  seed_bare_repo "$upstream_b" "b upstream"
  seed_bare_repo "$upstream_c" "c upstream"
  cd "$monorepo"
  dropped="$(git rev-parse HEAD)"
  run splice pull --recursive vendor/a
  [ "$status" -ne 0 ]
  git cherry-pick --abort
  git reset -q --hard HEAD~1
  run splice pull --recursive vendor/a
  [ "$status" -eq 0 ]
  ! git merge-base --is-ancestor "$dropped" HEAD
}

@test "nested: pull --recursive --branch pulls that branch for a splice the pull above adds too" {
  scenario_nested_splices "$monorepo" "$upstream"
  local upstream_e="$BATS_TEST_TMPDIR/upstream-e.git"
  make_bare_repo "$upstream_e"
  seed_bare_repo "$upstream_e" "e seed"
  seed_bare_repo "$upstream_e" "e release" release
  seed_bare_repo "$upstream_b" "b release" release
  work_in_upstream_a
  splice clone "$upstream_e" e
  git push -q origin HEAD:main HEAD:release
  seed_bare_repo "$upstream_e" "e upstream"
  cd "$monorepo"
  run splice pull --recursive --branch release vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/e/file.txt)" = "e seed"$'\n'"e release" ]
}

@test "nested: pull --recursive makes one commit of pulls of a splice whose path isn't ASCII" {
  local upstream_c="$BATS_TEST_TMPDIR/upstream-c.git" work
  make_bare_repo "$upstream_c"
  seed_bare_repo "$upstream_c" "c seed"
  make_bare_repo "$upstream_b"
  seed_bare_repo "$upstream_b" "b seed"
  work="$BATS_TEST_TMPDIR/b-work"
  git clone -q "$upstream_b" "$work"
  git -C "$work" config user.name "Test"
  git -C "$work" config user.email "test@example.com"
  add_splice "$work" "$upstream_c" é
  git -C "$work" push -q origin HEAD:main
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream_b" vendor/b
  fetch_splice "$monorepo" "$upstream_c"
  seed_bare_repo "$upstream_b" "b upstream"
  seed_bare_repo "$upstream_c" "c upstream"
  cd "$monorepo"
  run splice pull --recursive vendor/b
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 pulls made one commit"* ]]
}

@test "nested: pull and merge refuse a splice and one inside it, whose pull decides what's there" {
  scenario_three_levels "$monorepo" "$upstream"
  cd "$monorepo"
  for command in pull merge; do
    run splice "$command" vendor/a vendor/a/b/c
    [ "$status" -ne 0 ]
    [[ "$output" == *"vendor/a/b/c is inside vendor/a, whose $command decides what's there -- $command vendor/a with --recursive, or vendor/a/b/c in a command of its own"* ]]
  done
  run splice pull --recursive vendor/a/b/c vendor/a
  [ "$status" -ne 0 ]
  run splice push vendor/a vendor/a/b/c
  [ "$status" -eq 0 ]
}

# a's upstream splices e in at e/, at "e seed"; then e's upstream moves on.
e_added_in_upstream_a() {
  upstream_e="$BATS_TEST_TMPDIR/upstream-e.git"
  make_bare_repo "$upstream_e"
  seed_bare_repo "$upstream_e" "e seed"
  work_in_upstream_a
  splice clone "$upstream_e" e >/dev/null
  git push -q origin HEAD:main
  seed_bare_repo "$upstream_e" "e upstream"
  cd "$monorepo"
}

@test "nested: pull fetches a splice its merge brings in, and leaves pulling it to the next pull" {
  scenario_nested_splices "$monorepo" "$upstream"
  e_added_in_upstream_a
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a/e fetched"*"vendor/a: pulled"* ]]
  [[ "$output" != *"vendor/a/e: pulled"* ]]
  [ "$(splice_state vendor/a/e)" = "pull" ]
}

@test "nested: pull whose fetch of a splice it would bring in fails doesn't pull, and says so" {
  scenario_nested_splices "$monorepo" "$upstream"
  e_added_in_upstream_a
  mv "$upstream_e" "$upstream_e.gone"
  head=$(git rev-parse HEAD)
  run splice pull vendor/a
  [ "$status" -ne 0 ]
  [[ "$output" == *"vendor/a: not pulled, since vendor/a/e below it wasn't fetched"* ]]
  [[ "$output" == *"Not fetched: vendor/a/e"* ]]
  [ "$(git rev-parse HEAD)" = "$head" ]
}

@test "nested: clone fetches the splices the upstream has inside it" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  run splice clone "$upstream" vendor/x
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/x: cloned"*"vendor/x/b fetched"* ]]
  [ "$(splice_state vendor/x/b)" = "up-to-date" ]
}

@test "nested: clone whose fetch of a splice inside fails keeps the clone" {
  scenario_nested_splices "$monorepo" "$upstream"
  mv "$upstream_b" "$upstream_b.gone"
  cd "$monorepo"
  run splice clone "$upstream" vendor/x
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/x: cloned"* ]]
  [[ "$output" == *"vendor/x/b"* ]]
  git cat-file -e HEAD:vendor/x/b/.splice
}

@test "nested: pull --all pulls a splice the pull above adds, like --recursive" {
  scenario_nested_splices "$monorepo" "$upstream"
  e_added_in_upstream_a
  run splice pull --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a/e fetched"*"vendor/a/e: pulled"* ]]
  [ "$(cat vendor/a/e/file.txt)" = "e seed"$'\n'"e upstream" ]
}

@test "nested: pull --all makes one commit per splice it starts from, of its own pull and the ones below" {
  scenario_nested_splices "$monorepo" "$upstream"
  local upstream_x="$BATS_TEST_TMPDIR/upstream-x.git"
  make_bare_repo "$upstream_x"
  seed_bare_repo "$upstream_x" "x seed"
  add_splice "$monorepo" "$upstream_x" vendor/x
  seed_bare_repo "$upstream" "a upstream"
  seed_bare_repo "$upstream_b" "b upstream"
  seed_bare_repo "$upstream_x" "x upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run splice pull --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: 2 pulls made one commit"* ]]
  [ "$(git rev-list --count "$before..HEAD")" = 2 ]
  [[ "$(git log -1 --format=%s HEAD~1)" == "splice: pull vendor/a from main at "* ]]
  [[ "$(git log -1 --format=%b HEAD~1)" == "splice: pull vendor/a/b from main at "* ]]
  [[ "$(git log -1 --format=%s)" == "splice: pull vendor/x from main at "* ]]
}

@test "nested: a recursive pull's commit takes its message from the template, for its own pull and the ones below" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "a upstream"
  seed_bare_repo "$upstream_b" "b upstream"
  cd "$monorepo"
  run splice pull --recursive --message-template 'chore(deps): pull {path} to {new}

{shortlog}' vendor/a
  [ "$status" -eq 0 ]
  [[ "$(git log -1 --format=%s)" == "chore(deps): pull vendor/a to "* ]]
  [[ "$(git log -1 --format=%B)" == *"chore(deps): pull vendor/a/b to "*"b upstream"* ]]
}

@test "nested: pull --all stops at a copy of a splice it's inside, which would bring in the next copy" {
  load '../09-scenarios/05-nested-splices/04-cycle/setup'
  scenario_cycle "$monorepo" "$BATS_TEST_TMPDIR/up"
  cd "$monorepo"
  splice pull vendor/a >/dev/null
  run splice pull --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a/i/vendor/a: a copy of vendor/a, which it's inside -- not pulled"* ]]
  ! git cat-file -e HEAD:vendor/a/i/vendor/a/i/.splice
}

# The monorepo's own commit since the last pull: notes in vendor/a/b,
# which no upstream changes.
commit_m1() {
  echo "m1" >vendor/a/b/notes.txt
  git add vendor/a/b/notes.txt
  git commit -q -m "m1: notes in b"
}

@test "nested: pull --rebase --recursive pulls first, then rebases the monorepo's own commits onto the pulls once" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "a upstream"
  seed_bare_repo "$upstream_b" "b upstream"
  cd "$monorepo"
  commit_m1
  run splice pull --rebase --recursive vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: 2 pulls made one commit"*"rebased 1 commit of 'main' onto the pull"* ]]
  [ "$(git symbolic-ref --short HEAD)" = main ]
  [ "$(git log -1 --format=%s)" = "m1: notes in b" ]
  [[ "$(git log -1 --format=%s HEAD~1)" == "splice: pull vendor/a from main at "* ]]
  [ "$(git cat-file -p HEAD:vendor/a/b/notes.txt)" = m1 ]
}

@test "nested: pull --rebase --recursive stopped by a conflict in a pull leaves the branch as it was, and goes on when run again" {
  scenario_nested_splices "$monorepo" "$upstream"
  b_changed_in_upstream_a
  seed_bare_repo "$upstream_b" "b upstream"
  cd "$monorepo"
  commit_m1
  local before
  before="$(git rev-parse main)"
  run splice pull --rebase --recursive vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/b: conflict -- resolve it, then 'git commit'"* ]]
  [[ "$output" == *"The pulls are on a detached HEAD, 'main' is as it was"* ]]
  [ "$(git rev-parse main)" = "$before" ]
  echo resolved >vendor/a/b/file.txt
  git add vendor/a/b/file.txt
  git commit -q --no-edit
  run splice pull --rebase --recursive vendor/a
  [ "$status" -eq 0 ]
  [ "$(git symbolic-ref --short HEAD)" = main ]
  [ "$(git log -1 --format=%s)" = "m1: notes in b" ]
  [ "$(git cat-file -p HEAD:vendor/a/b/file.txt)" = resolved ]
}

@test "nested: a pull --rebase --recursive given up with git switch is forgotten" {
  scenario_nested_splices "$monorepo" "$upstream"
  b_changed_in_upstream_a
  seed_bare_repo "$upstream_b" "b upstream"
  cd "$monorepo"
  commit_m1
  run splice pull --rebase --recursive vendor/a
  [ "$status" -eq 1 ]
  git cherry-pick --abort
  git switch -q main
  run splice pull --recursive vendor/a
  [[ "$output" != *"under way"* ]]
  [[ "$output" == *"vendor/a: pulled"* ]]
}

@test "nested: pull --recursive without --rebase refuses while a pull --rebase --recursive is under way" {
  scenario_nested_splices "$monorepo" "$upstream"
  b_changed_in_upstream_a
  seed_bare_repo "$upstream_b" "b upstream"
  cd "$monorepo"
  commit_m1
  run splice pull --rebase --recursive vendor/a
  [ "$status" -eq 1 ]
  git commit -q -a --no-edit
  run splice pull --recursive vendor/a
  [ "$status" -ne 0 ]
  [[ "$output" == *"a 'pull --rebase --recursive' is under way for 'main' -- re-run it, or 'git switch main' to give up"* ]]
}

@test "nested: pull --rebase --recursive refuses a merge commit since the last pull, and changes nothing" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "a upstream"
  cd "$monorepo"
  git switch -q -c side
  commit_m1
  git switch -q main
  git merge -q --no-ff -m "merge side" side
  local before
  before="$(git rev-parse HEAD)"
  run splice pull --rebase --recursive vendor/a
  [ "$status" -ne 0 ]
  [[ "$output" == *"there's a merge commit since the last pull"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ "$(git symbolic-ref --short HEAD)" = main ]
}

@test "nested: pull --rebase --recursive refuses changes in the work tree, and changes nothing" {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "a upstream"
  cd "$monorepo"
  commit_m1
  echo "uncommitted" >>vendor/a/b/notes.txt
  run splice pull --rebase --recursive vendor/a
  [ "$status" -ne 0 ]
  [[ "$output" == *"the work tree has changes"* ]]
  [ "$(git symbolic-ref --short HEAD)" = main ]
  [ "$(cat vendor/a/b/notes.txt)" = "m1
uncommitted" ]
}

@test "nested: pull --rebase --recursive with nothing to pull leaves the branch's commits as they are" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  commit_m1
  local before
  before="$(git rev-parse HEAD)"
  run splice pull --rebase --recursive vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ "$(git symbolic-ref --short HEAD)" = main ]
}

@test "nested: pull --rebase --recursive with nothing to pull says so, even with published commits since the last pull" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  commit_m1
  git update-ref refs/remotes/origin/main HEAD
  run splice pull --rebase --recursive vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: nothing to pull"*"vendor/a/b: nothing to pull"* ]]
}

@test "nested: pull --rebase --recursive refuses, as --rebase does, when the upstream branch lacks the synced commit and its reflog doesn't show it had it" {
  load '../09-scenarios/06-rewritten-history/04-patch-branch-rebased/setup'
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  git clone -q "$monorepo" "$BATS_TEST_TMPDIR/clone"
  cd "$BATS_TEST_TMPDIR/clone"
  local before synced
  before="$(git rev-parse HEAD)"
  synced="$(splice_config vendor/a commit)"
  run splice pull --rebase --recursive vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: 'patches' lacks the synced commit ${synced:0:7}, and its reflog here doesn't show it ever had it -- --rebase would drop that commit's changes"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
  git symbolic-ref -q HEAD
}

@test "nested: in a clone of a's upstream, whose record of b names a commit b's upstream never got, pull --rebase refuses and pull merges it" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local" notes.txt
  seed_bare_repo "$upstream_b" "b upstream" main other.txt
  cd "$monorepo"
  ! splice push vendor/a/b >/dev/null 2>&1
  splice push vendor/a >/dev/null
  work_in_upstream_a
  run splice pull --rebase b
  [ "$status" -eq 1 ]
  [[ "$output" == *"b: synced commit"*"was made again here -- --rebase doesn't replay what's above"* ]]
  run splice pull b
  [ "$status" -eq 0 ]
  [ "$(splice_config b commit)" = "$(git -C "$upstream_b" rev-parse main)" ]
  [ "$(cat b/notes.txt)" = "b local" ]
  [ -f b/other.txt ]
}

@test "nested: a pull of the splice above keeps the monorepo's own change to the .splice below, besides the record its push wrote" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push --all >/dev/null
  local mirror="$BATS_TEST_TMPDIR/mirror-b.git"
  git clone -q --bare "$upstream_b" "$mirror"
  git config --file vendor/a/b/.splice upstream.fork.url "$mirror"
  git commit -q -am "b gets a fork"
  seed_bare_repo "$upstream_b" "b upstream" main other.txt
  git -C "$mirror" fetch -q "$upstream_b" "+refs/heads/*:refs/heads/*"
  work_in_upstream_a
  splice pull b >/dev/null
  git push -q origin main
  cd "$monorepo"
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" != *CONFLICT* ]]
  [ "$(git config --file vendor/a/b/.splice upstream.fork.url)" = "$mirror" ]
  [ "$(splice_config vendor/a/b commit)" = "$(git -C "$upstream_b" rev-parse main)" ]
}

@test "nested: a splice made by init below another, pushed only with the one above, is made again in a clone of the upstream above, which can push it" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "a seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" vendor/a
  local upstream_n="$BATS_TEST_TMPDIR/upstream-n.git"
  make_bare_repo "$upstream_n"
  cd "$monorepo"
  mkdir vendor/a/n
  echo "n" >vendor/a/n/file.txt
  git add vendor/a/n
  git commit -q -m "add n"
  splice init vendor/a/n "$upstream_n" >/dev/null
  splice push vendor/a >/dev/null
  work_in_upstream_a
  splice fetch n >/dev/null
  run splice status n
  [ "$status" -eq 0 ]
  [[ "$output" != *"isn't here"* ]]
  [[ "$output" != *"never fetched"* ]]
  run splice push n
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream_n" rev-parse main)" = "$(splice_config n commit)" ]
}

@test "nested: push --rebuilt-commit takes the rebuild of the splice above, whose record of the one below the rebuild wrote" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  run splice push --rebuilt-commit "$(splice rebuild vendor/a)" vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: pushed"* ]]
}

@test "nested: a bump of the splice above right after a push of both leaves it up to date" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push --all >/dev/null
  splice pull --bump vendor/a >/dev/null
  run splice status vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date  vendor/a"* ]]
}

@test "nested: the upstream above gets the folder of the splice below as the commit its record names, records inside it included" {
  scenario_three_levels "$monorepo" "$upstream"
  local b_work="$BATS_TEST_TMPDIR/b-work"
  git clone -q "$upstream_b" "$b_work"
  echo "c in b's upstream" >>"$b_work/c/file.txt"
  git -C "$b_work" -c user.name=Test -c user.email=test@example.com commit -q -am "c in b's upstream"
  git -C "$b_work" push -q origin main
  cd "$monorepo"
  splice pull vendor/a/b >/dev/null
  splice push --all >/dev/null
  local recorded
  recorded="$(git -C "$upstream" show main:b/.splice | git config --file - splice.commit)"
  [ "$(git -C "$upstream" rev-parse main:b/c/.splice)" = "$(git -C "$upstream_b" rev-parse "$recorded:c/.splice")" ]
  work_in_upstream_a
  splice fetch >/dev/null
  run splice status b
  [[ "$output" == *"up to date  b"* ]]
}

@test "nested: a change below and its revert leave the record of the splice above as it was, as the push below sends nothing" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  echo "b local" >>vendor/a/b/file.txt
  git commit -q -am "b local"
  git revert --no-edit HEAD >/dev/null
  commit_local "$monorepo" vendor/a "a local" other.txt
  run splice push --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a/b: nothing to push"* ]]
  [ "$(git -C "$upstream" show main:b/.splice | git config --file - splice.commit)" = "$(git -C "$upstream_b" rev-parse main)" ]
}

# The monorepo changes b and pushes only a, so a's upstream records b's
# rebuild, which b's upstream never got; then b's upstream moves on.
pushed_above_alone() {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push vendor/a >/dev/null
  seed_bare_repo "$upstream_b" "b upstream" main other.txt
}

@test "nested: a pull above keeps the monorepo's later pull below, when the upstream above didn't change its record" {
  pushed_above_alone
  splice pull vendor/a/b >/dev/null
  local pulled
  pulled="$(splice_config vendor/a/b commit)"
  seed_bare_repo "$upstream" "a upstream" main other.txt
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a/b commit)" = "$pulled" ]
}

@test "nested: a pull above takes the upstream's record of a splice below that moved here since the push, without a conflict" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local" notes.txt
  cd "$monorepo"
  splice push --all >/dev/null
  git mv vendor/a/b vendor/a/renamed
  git commit -q -m "rename b"
  seed_bare_repo "$upstream_b" "b upstream"
  work_in_upstream_a
  splice pull b >/dev/null
  git push -q origin main
  cd "$monorepo"
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" != *CONFLICT* ]]
  [ "$(splice_config vendor/a/renamed commit)" = "$(git -C "$upstream_b" rev-parse main)" ]
}

@test "nested: a change below and its revert, after a pull that brought changes from the upstream above, leave the record as push leaves the splice: up to date" {
  scenario_three_levels "$monorepo" "$upstream"
  local b_work="$BATS_TEST_TMPDIR/b-work"
  git clone -q "$upstream_b" "$b_work"
  echo "c in b's upstream" >>"$b_work/c/file.txt"
  git -C "$b_work" -c user.name=Test -c user.email=test@example.com commit -q -am "c in b's upstream"
  git -C "$b_work" push -q origin main
  cd "$monorepo"
  splice pull vendor/a/b >/dev/null
  echo "b local" >>vendor/a/b/file.txt
  git commit -q -am "b local"
  git revert --no-edit HEAD >/dev/null
  splice push --all >/dev/null
  work_in_upstream_a
  splice fetch >/dev/null
  run splice status b
  [[ "$output" == *"up to date  b"* ]]
}

@test "nested: the rebuild of the splice above doesn't mind a changed file in the work tree at a path like the one below" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  mkdir b
  echo "elsewhere" >b/file.txt
  git add b
  git commit -q -m "a folder b elsewhere"
  echo "uncommitted" >>vendor/a/b/file.txt
  run splice rebuild vendor/a
  [ "$status" -eq 0 ]
  run splice status vendor/a
  [[ "$output" == *"vendor/a"* ]]
  [[ "$output" != *"staged content"* ]]
}

@test "nested: a clone that fetched only the splice above says the one below is needed for its rebuild, instead of reading as diverged" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push --all >/dev/null
  local clone="$BATS_TEST_TMPDIR/clone"
  git clone -q --no-local "$monorepo" "$clone"
  cd "$clone"
  splice fetch vendor/a >/dev/null
  run splice status vendor/a
  [[ "$output" == *"vendor/a/b: can't be rebuilt here, and the rebuild of the splice around it records it -- 'git splice fetch vendor/a/b' fetches what it needs"* ]]
  [[ "$output" != *"ahead 1, behind 1"* ]]
  splice fetch vendor/a/b >/dev/null
  run splice status vendor/a
  [[ "$output" == *"up to date  vendor/a"* ]]
}

@test "nested: a clone that fetched the two splices above names the third one below as needed for their rebuilds" {
  scenario_three_levels "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b/c "c local"
  cd "$monorepo"
  splice push --all >/dev/null
  local clone="$BATS_TEST_TMPDIR/clone"
  git clone -q --no-local "$monorepo" "$clone"
  cd "$clone"
  splice fetch vendor/a vendor/a/b >/dev/null
  run splice status vendor/a
  [[ "$output" == *"vendor/a/b/c: can't be rebuilt here, and the rebuild of the splice around it records it -- 'git splice fetch vendor/a/b/c' fetches what it needs"* ]]
  [[ "$output" != *"'git splice fetch vendor/a/b'"* ]]
  splice fetch vendor/a/b/c >/dev/null
  run splice status vendor/a
  [[ "$output" == *"up to date  vendor/a"* ]]
}

@test "nested: pull --rebase of the splice above, after a push, a bump and a pull of the one below, doesn't conflict in the record below" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  cd "$monorepo"
  splice push --all >/dev/null
  splice pull --bump vendor/a >/dev/null
  seed_bare_repo "$upstream_b" "b upstream" main other.txt
  splice pull vendor/a/b >/dev/null
  seed_bare_repo "$upstream" "a upstream" main other.txt
  run splice pull --rebase vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" != *CONFLICT* ]]
  [ "$(splice_config vendor/a/b commit)" = "$(git -C "$upstream_b" rev-parse main)" ]
}

# The records written by the rebuild agree everywhere, after a push of
# everything from the monorepo in $monorepo, three levels deep: the
# monorepo reads up to date; each upstream records what the one inside it
# has; a clone of a's upstream reads up to date; a fresh
# clone of the monorepo rebuilds every splice to the same commits; and a
# pull of vendor/a after an unrelated change upstream keeps the monorepo's
# records of the splices inside it.
records_agree() {
  local upstream_c="$BATS_TEST_TMPDIR/upstream-c.git" path records
  cd "$monorepo"
  run splice push --all
  [ "$status" -eq 0 ] || { echo "push --all: $output" >&2; return 1; }
  run splice status
  [[ "$output" != *ahead* && "$output" != *behind* && "$output" != *"??"* ]] || { echo "monorepo: $output" >&2; return 1; }
  # Each upstream records what the one inside it has (#458).
  local parent child_url parent_url
  for path in $(git ls-files '*/.splice' | sed 's|/.splice$||'); do
    parent="$(dirname "$path")"
    while [ "$parent" != . ] && [ ! -f "$parent/.splice" ]; do parent="$(dirname "$parent")"; done
    [ "$parent" = . ] && continue
    parent_url="$(git config --file "$parent/.splice" upstream.origin.url)"
    child_url="$(git config --file "$path/.splice" upstream.origin.url)"
    [ "$(git -C "$parent_url" show "main:${path#"$parent"/}/.splice" | git config --file - splice.commit)" = "$(git -C "$child_url" rev-parse main)" ] || { echo "the upstream of $parent records another commit for $path" >&2; return 1; }
  done
  local a_clone="$BATS_TEST_TMPDIR/a-clone"
  git clone -q "$upstream" "$a_clone"
  (cd "$a_clone" && splice fetch >/dev/null 2>&1)
  run bash -c "cd '$a_clone' && git splice status"
  [[ "$output" != *ahead* && "$output" != *behind* && "$output" != *"??"* ]] || { echo "clone of a's upstream: $output" >&2; return 1; }
  local fresh="$BATS_TEST_TMPDIR/fresh"
  git clone -q --no-local "$monorepo" "$fresh"
  (cd "$fresh" && splice fetch >/dev/null 2>&1)
  for path in $(git ls-files '*.splice' | sed 's|/.splice$||'); do
    [ "$(cd "$fresh" && splice rebuild "$path")" = "$(splice rebuild "$path")" ] || { echo "fresh clone rebuilds $path otherwise" >&2; return 1; }
  done
  records="$(git ls-files -s '*.splice' | grep -v '^.* vendor/a/.splice$')"
  records="$(for path in $(git ls-files 'vendor/a/*/.splice' 'vendor/a/**/.splice' | sed 's|/.splice$||' | sort -u); do echo "$path $(splice_config "$path" commit)"; done)"
  seed_bare_repo "$upstream" "a moves on" main unrelated.txt
  run splice pull vendor/a
  [ "$status" -eq 0 ] || { echo "pull vendor/a: $output" >&2; return 1; }
  [ "$(for path in $(git ls-files 'vendor/a/*/.splice' 'vendor/a/**/.splice' | sed 's|/.splice$||' | sort -u); do echo "$path $(splice_config "$path" commit)"; done)" = "$records" ] || { echo "the pull of vendor/a changed the records below it" >&2; return 1; }
}

@test "nested: records agree everywhere after a change in the innermost splice" {
  scenario_three_levels "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b/c "c local"
  records_agree
}

@test "nested: records agree everywhere after changes in every splice" {
  scenario_three_levels "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "a local" other.txt
  commit_local "$monorepo" vendor/a/b "b local" notes.txt
  commit_local "$monorepo" vendor/a/b/c "c local"
  records_agree
}

@test "nested: records agree everywhere after a push and a bump of the outermost splice" {
  scenario_three_levels "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b/c "c local"
  cd "$monorepo"
  splice push --all >/dev/null
  splice pull --bump vendor/a >/dev/null
  commit_local "$monorepo" vendor/a/b/c "c again"
  records_agree
}

@test "nested: records agree everywhere after a pull of the innermost splice between two pushes" {
  scenario_three_levels "$monorepo" "$upstream"
  local upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  commit_local "$monorepo" vendor/a/b/c "c local"
  cd "$monorepo"
  splice push --all >/dev/null
  seed_bare_repo "$upstream_c" "c upstream" main other.txt
  splice pull vendor/a/b/c >/dev/null
  records_agree
}

@test "nested: records agree everywhere after a change and its revert in the middle splice" {
  scenario_three_levels "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b/c "c local"
  cd "$monorepo"
  echo "b local" >>vendor/a/b/notes.txt
  git add vendor/a/b/notes.txt
  git commit -q -m "b local"
  git revert --no-edit HEAD >/dev/null
  records_agree
}

@test "nested: records agree everywhere after the innermost splice moved within the one around it" {
  scenario_three_levels "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b/c "c local"
  cd "$monorepo"
  splice push --all >/dev/null
  git mv vendor/a/b/c vendor/a/b/moved
  git commit -q -m "move c"
  records_agree
}

@test "nested: records agree everywhere after a push of the outermost splice alone, then a pull of the one below" {
  scenario_three_levels "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local" notes.txt
  cd "$monorepo"
  splice push vendor/a >/dev/null
  seed_bare_repo "$upstream_b" "b upstream" main other.txt
  splice pull vendor/a/b >/dev/null
  records_agree
}
