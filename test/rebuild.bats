# The push rebuild, checked against `git subtree split` as the test oracle:
# where both apply, the rebuild must make byte-identical commits. Where it
# deliberately differs, the test says so and asserts exactly how ("approved
# divergence"). See docs/design/README.md.

setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/push-ahead/setup'
  load 'scenarios/diverged-then-pulled/setup'
  load 'scenarios/squash-merged-pull/setup'
  load 'scenarios/init-new-upstream/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

# A monorepo whose vendor/a was added by `git subtree add --squash`, which
# split understands. Sets B (the add's merge, i.e. the boundary) and U (the
# upstream commit it added). No .splice: split would put it in every tree.
oracle_fixture() {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git subtree add -q --prefix=vendor/a "$upstream" main --squash >/dev/null 2>&1
  B="$(git rev-parse HEAD)"
  U="$(git ls-remote "$upstream" refs/heads/main | cut -f1)"
}

split() {
  git -c commit.gpgSign=false subtree split -q --prefix=vendor/a HEAD 2>/dev/null
}

@test "rebuild: a linear history rebuilds into exactly the commits git subtree split makes" {
  oracle_fixture
  commit_local "$monorepo" "vendor/a" "first"
  commit_local "$monorepo" "." "outside the splice" outside.txt
  (
    echo both >>vendor/a/file.txt
    echo both >>outside.txt
    git commit -q -am "touches the splice and outside"
  )
  commit_local "$monorepo" "vendor/a" "second" sub/dir/file.txt
  local rebuilt
  rebuilt="$(rebuild_walk vendor/a "$U" "$B..HEAD")"
  [ "$(git rev-list --count "$U..$rebuilt")" -eq 3 ]
  [ "$rebuilt" = "$(split)" ]
}

@test "rebuild: approved divergence: a merge in the monorepo becomes one ordinary commit" {
  oracle_fixture
  git checkout -q -b feature
  commit_local "$monorepo" "vendor/a" "feature work" feature.txt
  local before_merge
  before_merge="$(rebuild_walk vendor/a "$U" "$B..HEAD")"
  git checkout -q main
  commit_local "$monorepo" "vendor/a" "main work" main.txt
  git checkout -q feature
  git merge -q --no-edit main
  commit_local "$monorepo" "vendor/a" "after the merge" feature.txt

  local ours theirs
  ours="$(rebuild_walk vendor/a "$U" "$B..HEAD")"
  theirs="$(split)"
  # Up to the merge, both are the same commits.
  [ "$(git rev-parse "$theirs~2")" = "$before_merge" ]
  [ "$(git rev-parse "$ours~2")" = "$before_merge" ]
  # split keeps the merge, and "main work" as its own commit...
  [ "$(git rev-list --count --merges "$theirs")" -eq 1 ]
  git log --format=%s "$theirs" | grep -qx "main work"
  # ...the rebuild has one commit that carries main's change.
  [ "$(git rev-list --count --merges "$ours")" -eq 0 ]
  ! git log --format=%s "$ours" | grep -qx "main work"
  [ "$(git log -1 --format=%s "$ours~1")" = "Merge branch 'main' into feature" ]
  git cat-file -e "$ours~1:main.txt"
  # Same content in the end.
  [ "$(git rev-parse "$ours^{tree}")" = "$(git rev-parse "$theirs^{tree}")" ]
}

@test "rebuild: is deterministic, even when commits would be signed" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config commit.gpgSign true
  local first
  first="$(rebuild_splice vendor/a)"
  [ -n "$first" ]
  [ "$(rebuild_splice vendor/a)" = "$first" ]
}

@test "rebuild: starts at the synced commit and leaves .splice out" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a)"
  [ "$(git rev-parse "$rebuilt^")" = "$(splice_config vendor/a commit)" ]
  [ "$(git log -1 --format=%s "$rebuilt")" = "local change" ]
  ! git cat-file -e "$rebuilt:.splice" 2>/dev/null
}

@test "rebuild: is the synced commit itself when nothing changed locally" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  [ "$(rebuild_splice vendor/a HEAD^)" = "$(splice_config vendor/a commit)" ]
}

@test "rebuild: without a synced commit (after init), rebuilds the folder's whole history" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  printf '[splice]\n\turl = %s\n' "$upstream" >lib/a/.splice
  git add lib/a/.splice
  git commit -q -m "init lib/a"
  local rebuilt
  rebuilt="$(rebuild_splice lib/a)"
  [ "$(git log --format=%s "$rebuilt")" = "second version"$'\n'"first version" ]
  [ -z "$(git rev-parse "$rebuilt~1^@")" ]
}

@test "rebuild: a pull that merged a divergence keeps the unpushed commit and joins upstream with a merge" {
  scenario_diverged_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt synced
  rebuilt="$(rebuild_splice vendor/a)"
  synced="$(splice_config vendor/a commit)"
  [ "$(git rev-parse "$rebuilt^2")" = "$synced" ]
  [ "$(git log -1 --format=%s "$rebuilt^1")" = "local change" ]
  [ "$(git rev-parse "$rebuilt^1^")" = "$(git rev-parse "$synced^")" ]
}

@test "rebuild: approved divergence: a squash-merged pull doesn't repeat upstream's commit" {
  scenario_squash_merged_pull "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt feature_tip
  rebuilt="$(rebuild_splice vendor/a)"
  feature_tip="$(git rev-parse refs/splices/vendor/a/feature)"
  # The squash merge is the boundary: the rebuild starts at the pulled
  # upstream commit itself, then only the local change follows.
  [ "$(git rev-parse "$rebuilt^")" = "$feature_tip" ]
  [ "$(git log -1 --format=%s "$rebuilt")" = "local change" ]
  [ "$(git log --format=%s "$rebuilt" | grep -c "upstream feature work")" -eq 1 ]
}

@test "rebuild: a rebased pull still starts at its synced commit" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  seed_bare_repo "$upstream" "upstream feature work" feature
  cd "$monorepo"
  git checkout -q -b feature
  splice pull vendor/a >/dev/null 2>&1
  commit_local "$monorepo" "vendor/a" "local change"
  git checkout -q main
  commit_local "$monorepo" "." "meanwhile on main" other.txt
  git checkout -q feature
  local pulled
  pulled="$(git rev-parse HEAD^)"
  git rebase -q main
  [ "$(git rev-parse HEAD^)" != "$pulled" ]
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a)"
  [ "$(git log -1 --format=%s "$rebuilt")" = "local change" ]
  [ "$(git rev-parse "$rebuilt^")" = "$(git rev-parse refs/splices/vendor/a/feature)" ]
}

@test "rebuild: a synced commit that isn't available locally is an error" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice splice.commit 1234567890123456789012345678901234567890
  git commit -q -am "point at a missing commit"
  run rebuild_splice vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"synced commit 1234567 isn't available locally"* ]]
}
