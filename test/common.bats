setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/up-to-date/setup'
  load 'scenarios/push-ahead/setup'
  load 'scenarios/shared-remote-url/setup'
  load 'scenarios/nested-splices/setup'
  load 'scenarios/feature-branch-unchanged/setup'
  load 'scenarios/feature-branch-changed/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "discover_splices finds every folder with a committed .splice" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p untracked && echo x >untracked/.splice
  discover_splices
  [ "${ALL_PATHS[*]}" = "vendor/a vendor/b" ]
}

@test "discover_splices is empty without .splice files" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  discover_splices
  [ ${#ALL_PATHS[@]} -eq 0 ]
}

@test "discover_splices refuses nested splices" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  run discover_splices
  [ "$status" -eq 1 ]
  [[ "$output" == *"nested splices are not supported: 'vendor/pkg' and 'vendor/pkg/extra' overlap"* ]]
}

@test "discover_splices: a file name with a newline doesn't make a splice" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p $'notes\nphantom'
  echo x >$'notes\nphantom/.splice'
  git add . && git commit -q -m "a file name with a newline"
  run discover_splices
  [ "$status" -eq 1 ]
  [[ "$output" == *"can't be part of a Git ref name"* ]]
  [[ "$output" != *"'phantom'"* ]]
}

@test "discover_splices reads HEAD, not the index" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  git rm -q --cached vendor/b/.splice
  mkdir -p vendor/c && echo "[splice]" >vendor/c/.splice && git add vendor/c/.splice
  discover_splices
  [ "${ALL_PATHS[*]}" = "vendor/a vendor/b" ]
}

@test "discover_splices refuses a path that can't be part of a ref" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p "my lib" && echo "[splice]" >"my lib/.splice"
  git add "my lib" && git commit -q -m "a splice by hand"
  run discover_splices
  [ "$status" -eq 1 ]
  [[ "$output" == *"'my lib' can't be part of a Git ref name"* ]]
}

@test "discover_splices refuses a .splice at the repository root" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  echo x >.splice
  git add .splice
  git commit -q -m "a .splice at the root"
  run discover_splices
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a folder"* ]]
}

@test "select_paths: splicing in or out needs paths or --all" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  discover_splices
  PATH_ARGS=() ALL_ARG=""
  run select_paths explicit push
  [ "$status" -eq 1 ]
  [[ "$output" == *"which splice?"*"vendor/a vendor/b"* ]]
  ALL_ARG=1
  select_paths explicit push
  [ "${SELECTED_PATHS[*]}" = "vendor/a vendor/b" ]
}

@test "select_paths: looking covers every splice by default" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  discover_splices
  PATH_ARGS=() ALL_ARG=""
  select_paths overview status
  [ "${SELECTED_PATHS[*]}" = "vendor/a vendor/b" ]
}

@test "select_paths: normalizes and deduplicates paths, and refuses others" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  discover_splices
  PATH_ARGS=(./vendor/b/ vendor/b) ALL_ARG=""
  select_paths explicit push
  [ "${SELECTED_PATHS[*]}" = "vendor/b" ]
  PATH_ARGS=(vendor)
  run select_paths explicit push
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a splice: vendor"* ]]
}

@test "select_paths: paths and --all together are refused" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  discover_splices
  PATH_ARGS=(vendor/a) ALL_ARG=1
  run select_paths explicit push
  [ "$status" -eq 1 ]
}

@test "parse_args: refuses options the command doesn't take" {
  usage() { echo usage; }
  run parse_args usage "--merge" --force vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option: --force"* ]]
  parse_args usage "--merge" --merge --base main -- --odd-path
  has_flag --merge
  [ "$BASE_ARG" = main ]
  [ "${PATH_ARGS[*]}" = "--odd-path" ]
}

@test "state_blob sets and unsets keys of the committed .splice" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  local blob
  blob="$(state_blob vendor/a commit=abc default-branch=master)"
  [ "$(git config --blob "$blob" splice.commit)" = abc ]
  [ "$(git config --blob "$blob" splice.default-branch)" = master ]
  [ "$(git config --blob "$blob" splice.url)" = "$upstream" ]
  blob="$(state_blob vendor/a default-branch=)"
  ! git config --blob "$blob" splice.default-branch
}

@test "upstream_branch_for maps only the monorepo's default branch to default-branch" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  [ "$(upstream_branch_for vendor/a main)" = main ]
  git config --file vendor/a/.splice splice.default-branch master
  git commit -q -am "upstream calls it master"
  [ "$(upstream_branch_for vendor/a main)" = master ]
  [ "$(upstream_branch_for vendor/a feature)" = feature ]
}

@test "folder_tree is empty for a missing folder or a file" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  [ -n "$(folder_tree HEAD vendor/a)" ]
  [ -z "$(folder_tree HEAD vendor/nope)" ]
  [ -z "$(folder_tree HEAD vendor/a/file.txt)" ]
}

@test "shell_quote leaves plain words alone and quotes everything else as one word" {
  [ "$(shell_quote vendor/a)" = "vendor/a" ]
  [ "$(shell_quote "it's x;y")" = "'it'\\''s x;y'" ]
}

# Gives the monorepo an "origin" of its own, with origin/HEAD pointing at
# main.
add_monorepo_origin() {
  local origin="$BATS_TEST_TMPDIR/monorepo-origin.git"
  make_bare_repo "$origin"
  git remote add origin "$origin"
  git push -q origin main
  git fetch -q origin
  git remote set-head origin main
}

@test "resolve_base_ref: prefers an explicit branch over the default branch" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git branch other main
  git config init.defaultBranch other
  run resolve_base_ref main
  [ "$output" = "refs/heads/main" ]
}

@test "resolve_base_ref: uses origin/HEAD before init.defaultBranch" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git branch trunk main
  git config init.defaultBranch trunk
  add_monorepo_origin
  run resolve_base_ref
  [ "$output" = "refs/heads/main" ]
}

@test "resolve_base_ref: a stale local branch doesn't hide the fresher origin/<name>" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  add_monorepo_origin
  local stale
  stale="$(git rev-parse main)"
  git checkout -q main
  commit_local "$monorepo" "vendor/a" "changed on main"
  git push -q origin main
  git checkout -q -b fresh origin/main
  git branch -q -f main "$stale"
  run resolve_base_ref
  [ "$output" = "refs/remotes/origin/main" ]
}

@test "resolve_base_ref: fails when nothing names a base branch" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git config --unset init.defaultBranch
  run resolve_base_ref
  [ "$status" -eq 1 ]
}

@test "resolve_base_ref: rejects a branch that shares no history with HEAD" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q --orphan orphan
  git commit -q --allow-empty -m "unrelated root"
  git checkout -q feature
  run resolve_base_ref orphan
  [ "$status" -eq 1 ]
}

@test "changes_vs_base: no when the splice is untouched on this branch" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  changes_vs_base vendor/a
  [ "$SPLICE_CHANGES_VS_BASE" = no ]
  [ "$SPLICE_BASE_BRANCH" = main ]
}

@test "changes_vs_base: yes when the splice changed on this branch" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  changes_vs_base vendor/a
  [ "$SPLICE_CHANGES_VS_BASE" = yes ]
  [ "$SPLICE_BASE_MERGE_BASE" = "$(git rev-parse main)" ]
}

@test "changes_vs_base: a change to .splice alone doesn't count" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice splice.default-branch other
  git commit -q -am "only .splice"
  changes_vs_base vendor/a
  [ "$SPLICE_CHANGES_VS_BASE" = no ]
}

@test "changes_vs_base: changes made on the base branch after the cut don't count" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q main
  commit_local "$monorepo" "vendor/a" "later, on main"
  git checkout -q feature
  changes_vs_base vendor/a
  [ "$SPLICE_CHANGES_VS_BASE" = no ]
}

@test "changes_vs_base: self on the base branch itself" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q main
  changes_vs_base vendor/a
  [ "$SPLICE_CHANGES_VS_BASE" = self ]
}

@test "changes_vs_base: unresolved without a base branch" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git config --unset init.defaultBranch
  changes_vs_base vendor/a
  [ "$SPLICE_CHANGES_VS_BASE" = unresolved ]
  [ -z "$SPLICE_BASE_REF" ]
}

@test "print_unrelated_history_guidance quotes names with shell metacharacters" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run print_unrelated_history_guidance "vendor/a"
  [[ "$output" == *"git splice push --force -- vendor/a"* ]]
  [[ "$output" == *"git rm -q -- vendor/a/.splice"* ]]
  run print_unrelated_history_guidance "x;id"
  [[ "$output" == *"git splice push --force -- 'x;id'"* ]]
  run print_unrelated_history_guidance "-foo"
  [[ "$output" == *"git rm -r -q -- -foo"* ]]
  [[ "$output" == *"git splice clone -- "*" -foo"* ]]
}
