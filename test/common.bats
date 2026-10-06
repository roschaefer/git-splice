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
  [[ "$output" == *"isn't supported as a splice path yet"* ]]
  [[ "$output" != *"'phantom'"* ]]
}

@test "discover_splices matches .splice literally, not as a pattern" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p notes && echo x >notes/xsplice && echo x >vendor/a/-splice
  git add . && git commit -q -m "files whose names only resemble .splice"
  discover_splices
  [ "${ALL_PATHS[*]}" = "vendor/a" ]
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
  [[ "$output" == *"'my lib' isn't supported as a splice path yet"* ]]
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
  [ "$(git config --blob "$blob" upstream.origin.url)" = "$upstream" ]
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

# Runs derive_upstream_key on $1 and checks that it gives key $2.
assert_derived_key() {
  derive_upstream_key "$1"
  echo "$1 -> $DERIVED_KEY" >&2
  [ "$DERIVED_KEY" = "$2" ]
  valid_upstream_key "$DERIVED_KEY"
}

@test "derive_upstream_key: the URL's last component, without .git" {
  assert_derived_key https://github.com/x/lib.git lib
  assert_derived_key git@github.com:x/lib.git lib
  assert_derived_key host:lib lib
  assert_derived_key /srv/git/lib/ lib
  assert_derived_key ../lib.git lib
}

@test "derive_upstream_key: lower case, with what a key can't hold replaced by -" {
  assert_derived_key https://host/Org/My_Lib.git my_lib
  assert_derived_key "https://host/a b~c" a-b-c
  assert_derived_key https://host/x.lock x-lock
  assert_derived_key https://host/.hidden..name hidden.name
  assert_derived_key "ext::sh -c sleep% 0;% exec% %S% /tmp/up" up
}

@test "derive_upstream_key: falls back to 'upstream' when nothing usable is left" {
  assert_derived_key https://host/ host
  assert_derived_key https://host/%%% upstream
  assert_derived_key / upstream
}

@test "derive_upstream_key: cuts long names, so suffixes still fit" {
  derive_upstream_key "https://host/$(printf 'a%.0s' {1..300})"
  [ "${#DERIVED_KEY}" -eq 40 ]
}

@test "valid_upstream_key: lower-case letters, digits, '.', '_' and '-' only" {
  valid_upstream_key lib
  valid_upstream_key lib-2
  valid_upstream_key my_lib.v2
  ! valid_upstream_key Lib
  ! valid_upstream_key -lib
  ! valid_upstream_key lib.
  ! valid_upstream_key a/b
  ! valid_upstream_key a..b
  ! valid_upstream_key ""
  ! valid_upstream_key "$(printf 'a%.0s' {1..65})"
}

@test "upstream_key: empty for an upstream never fetched" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  upstream_key https://github.com/x/lib.git
  [ -z "$UPSTREAM_KEY" ]
  [ -z "$(git config --local --get-regexp '^splice\.' || true)" ]
}

@test "create_upstream_key: records the key in the repository's config, and reuses it" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  create_upstream_key https://github.com/x/lib.git
  [ "$UPSTREAM_KEY" = lib ]
  [ "$(git config --local splice.lib.url)" = https://github.com/x/lib.git ]
  create_upstream_key https://github.com/x/lib.git
  [ "$UPSTREAM_KEY" = lib ]
  [ "$(git config --local --get-all splice.lib.url | wc -l)" -eq 1 ]
}

@test "create_upstream_key: URLs differing only in case get keys that differ in more than case" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  create_upstream_key ssh://host/Org/Lib
  [ "$UPSTREAM_KEY" = lib ]
  create_upstream_key ssh://host/org/lib
  [ "$UPSTREAM_KEY" = lib-2 ]
}

@test "create_upstream_key: skips a key whose refs are left over" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git update-ref refs/splices/lib/main HEAD
  create_upstream_key https://github.com/x/lib.git
  [ "$UPSTREAM_KEY" = lib-2 ]
}

@test "create_upstream_key: a key another command recorded meanwhile for another URL goes to that URL" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  load_upstream_keys
  git config --local --add splice.lib.url https://gitlab.com/y/lib.git
  create_upstream_key https://github.com/x/lib.git
  [ "$UPSTREAM_KEY" = lib-2 ]
  [ "$(git config --local --get-all splice.lib.url)" = https://gitlab.com/y/lib.git ]
  [ "$(git config --local --get-all splice.lib-2.url)" = https://github.com/x/lib.git ]
}

@test "create_upstream_key: the same URL recorded meanwhile under the same key is kept once" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  load_upstream_keys
  git config --local --add splice.lib.url https://github.com/x/lib.git
  create_upstream_key https://github.com/x/lib.git
  [ "$UPSTREAM_KEY" = lib ]
  [ "$(git config --local --get-all splice.lib.url)" = https://github.com/x/lib.git ]
}

@test "discover_splices refuses an old .splice and prints how to convert it" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  printf '[splice]\n\turl = %s\n\tcommit = %s\n' "$upstream" "$(splice_config vendor/a commit)" >vendor/a/.splice
  git commit -q -am "old format"
  run discover_splices
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "!!   vendor/a/.splice has its URL in the old format, splice.url -- convert it with:" ]]
  [[ "$output" == *"git config --file vendor/a/.splice upstream.origin.url $upstream"* ]]
  [[ "$output" == *"git config --file vendor/a/.splice --unset splice.url"* ]]
}

@test "discover_splices: the printed commands convert an old .splice" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  printf '[splice]\n\turl = %s\n\tcommit = %s\n' "$upstream" "$(splice_config vendor/a commit)" >vendor/a/.splice
  git commit -q -am "old format"
  run discover_splices
  eval "$(printf '%s\n' "$output" | grep '^  git ')"
  run "$BATS_TEST_DIRNAME/../git-splice" status
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a -> main (up to date)" ]
}

@test "discover_splices refuses a .splice without an upstream, with an empty URL, or with two" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice --remove-section upstream.origin
  git commit -q -am "no upstream"
  run discover_splices
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/.splice names no upstream"* ]]
  git config --file vendor/a/.splice upstream.origin.url ""
  git commit -q -am "empty upstream URL"
  run discover_splices
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/.splice names no upstream"* ]]
  git config --file vendor/a/.splice upstream.origin.url "$upstream"
  git config --file vendor/a/.splice upstream.fork.url "$BATS_TEST_TMPDIR/fork.git"
  git commit -q -am "two upstreams"
  run discover_splices
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/.splice names 2 upstreams -- only one is supported so far"* ]]
}

@test "discover_splices refuses a .splice git config can't read, with Git's message" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  printf '<<<<<<< HEAD\n' >>vendor/a/.splice
  git commit -q -am "conflict markers"
  # The entrypoint, so the error is printed under set -e as in real use.
  run "$BATS_TEST_DIRNAME/../git-splice" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/.splice can't be read (bad config line "*") -- fix it and commit it"* ]]
}

@test "discover_splices refuses a .splice that git config can't read from its first line" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  { printf '<<<<<<< HEAD\n'; cat vendor/a/.splice; } >vendor/a/.splice.new
  mv vendor/a/.splice.new vendor/a/.splice
  git commit -q -am "conflict markers first"
  run "$BATS_TEST_DIRNAME/../git-splice" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/.splice can't be read (bad config line 1 "*") -- fix it and commit it"* ]]
}

@test "discover_splices reads an upstream URL with a newline in it whole" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.origin.url $'/srv/a\nb.git'
  git commit -q -am "newline in the URL"
  discover_splices
  [ "${SPLICE_URLS[vendor/a]}" = $'/srv/a\nb.git' ]
}
