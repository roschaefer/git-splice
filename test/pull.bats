setup() {
  load 'helpers/fixtures'
  load_lib
  load 'scenarios/up-to-date/setup'
  load 'scenarios/pull-ahead/setup'
  load 'scenarios/diverged-common-ancestor/setup'
  load 'scenarios/diverged-unrelated-history/setup'
  load 'scenarios/shared-remote-url/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "pull: pulls cleanly when remote is ahead" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run pull_one "vendor/a" "main"
  [ "$status" -eq 0 ]
  run grep -qx "upstream change" vendor/a/file.txt
  [ "$status" -eq 0 ]
}

@test "pull: no-op when already up to date" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run pull_one "vendor/a" "main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to pull"* ]]
}

@test "pull: fetches the current branch even with a narrowed remote refspec" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  seed_bare_repo "$upstream" "feature change" "feature"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  cd "$monorepo"
  git checkout -q -b feature
  git config --unset-all remote.vendor/a.fetch
  git config --add remote.vendor/a.fetch "+refs/heads/main:refs/remotes/vendor/a/main"

  run cmd_pull vendor/a

  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: pulled"* ]]
  run grep -qx "feature change" vendor/a/file.txt
  [ "$status" -eq 0 ]
}

@test "pull: a remote without the current branch has nothing to pull, not a failed fetch" {
  local up_b="$BATS_TEST_TMPDIR/upstream-b.git"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  make_bare_repo "$up_b"
  seed_bare_repo "$up_b" "b seed"
  seed_bare_repo "$up_b" "b feature change" "feature"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  add_subtree "$monorepo" "$up_b" "vendor/b"
  cd "$monorepo"
  git checkout -q -b feature

  run cmd_pull

  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: remote has no 'feature' branch -- nothing to pull"* ]]
  [[ "$output" == *"vendor/b: pulled"* ]]
  [[ "$output" != *"couldn't find remote ref"* ]]
  [[ "$output" != *"fetch failed"* ]]
}

@test "pull: a branch deleted upstream has nothing to pull, and its stale tracking ref goes" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "feature seed" "feature"
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    git checkout -q -b feature
  )
  add_subtree "$monorepo" "$upstream" "vendor/a" "feature"
  cd "$monorepo"
  git tag local-only
  git config --add remote.vendor/a.fetch "+refs/tags/*:refs/tags/*"
  git -C "$upstream" update-ref -d refs/heads/feature

  run cmd_pull vendor/a

  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: remote has no 'feature' branch -- nothing to pull"* ]]
  [[ "$output" != *"couldn't find remote ref"* ]]
  run git show-ref --verify --quiet refs/remotes/vendor/a/feature
  [ "$status" -ne 0 ]
  run git show-ref --verify --quiet refs/tags/local-only
  [ "$status" -eq 0 ]
}

@test "pull: fails when the stale tracking ref of a branch deleted upstream can't be removed" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "feature seed" "feature"
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    git checkout -q -b feature
  )
  add_subtree "$monorepo" "$upstream" "vendor/a" "feature"
  cd "$monorepo"
  git pack-refs --all
  git -C "$upstream" update-ref -d refs/heads/feature
  mkdir -p .git/refs/remotes/vendor/a
  touch .git/refs/remotes/vendor/a/feature.lock

  run cmd_pull vendor/a

  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot lock ref 'refs/remotes/vendor/a/feature'"* ]]
  [[ "$output" == *"Failed: vendor/a"* ]]
  [[ "$output" != *"nothing to pull"* ]]
}

@test "pull: still fails when the remote can't be reached" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  cd "$monorepo"
  git remote set-url vendor/a "$BATS_TEST_TMPDIR/missing.git"

  run cmd_pull vendor/a

  [ "$status" -eq 1 ]
  [[ "$output" == *"does not appear to be a git repository"* ]]
  [[ "$output" == *"Failed: vendor/a"* ]]
}

@test "pull: ordinary conflict leaves MERGE_HEAD, resolved via plain git commit" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run pull_one "vendor/a" "main"
  [ "$status" -eq 1 ]
  [ -f .git/MERGE_HEAD ]

  git add vendor/a/file.txt
  git commit -q --no-edit
  [ ! -f .git/MERGE_HEAD ]
}

@test "pull: unrelated-history does not attempt a merge, prints guidance" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  run pull_one "vendor/a" "main"
  [ "$status" -eq 1 ]
  [ ! -f .git/MERGE_HEAD ]
  [[ "$output" == *"share no history"* ]]
  [[ "$output" == *"git subtree add --prefix=vendor/a"* ]]
}

@test "pull_one: refuses a path git-subtree cannot use, without attempting a merge" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  classify_subtree() { SUBTREE_STATE="pull"; SUBTREE_TARGET_REF="refs/heads/main"; SUBTREE_SPLIT_SHA=""; }

  run pull_one "-n" "main" skip-fetch

  [ "$status" -eq 1 ]
  [[ "$output" == *"git-subtree cannot use a name starting with '-'"* ]]
}

@test "pull_one: refuses a branch git-subtree cannot use, without fetching" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  fetch_one() { echo "fetch_one should not have been called" >&2; return 1; }

  run pull_one "vendor/a" "-n"

  [ "$status" -eq 1 ]
  [[ "$output" == *"git-subtree cannot use a branch name starting with '-'"* ]]
}

@test "pull: rechecks ancestry after fetching a missing split object" {
  local monorepo_origin="$BATS_TEST_TMPDIR/monorepo-origin.git"
  local fresh_monorepo="$BATS_TEST_TMPDIR/fresh-monorepo"
  local rewrite="$BATS_TEST_TMPDIR/rewrite"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  local old_split
  old_split="$(
    cd "$monorepo"
    sync_split_sha "$(find_sync_commit vendor/a)"
  )"
  git -C "$upstream" tag old-split "$old_split"
  git clone -q --bare "$monorepo" "$monorepo_origin"
  git clone -q "$monorepo_origin" "$fresh_monorepo"
  (
    git clone -q "$upstream" "$rewrite"
    cd "$rewrite"
    git config user.name "Test"
    git config user.email "test@example.com"
    git checkout -q --orphan unrelated-main
    rm -f file.txt
    echo "brand new unrelated history" >file.txt
    git add file.txt
    git commit -q -m "brand new unrelated history"
    git push -q --force origin HEAD:main
  )
  cd "$fresh_monorepo"
  git config user.name "Test"
  git config user.email "test@example.com"
  git remote add vendor/a "$upstream"
  git config --add remote.vendor/a.fetch "+refs/tags/*:refs/tags/*"

  run cmd_pull vendor/a

  [ "$status" -eq 1 ]
  [[ "$output" == *"share no history"* ]]
  [ ! -f .git/MERGE_HEAD ]
}

@test "pull: stops after a conflict instead of failing the remaining subtrees" {
  local upstream_b="$BATS_TEST_TMPDIR/upstream-b.git"
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  make_bare_repo "$upstream_b"
  seed_bare_repo "$upstream_b" "seed"
  add_subtree "$monorepo" "$upstream_b" "vendor/b"
  seed_bare_repo "$upstream_b" "upstream change"
  cd "$monorepo"

  run cmd_pull vendor/a vendor/b

  [ "$status" -eq 1 ]
  [ -f .git/MERGE_HEAD ]
  [[ "$output" == *"Failed: vendor/a"* ]]
  [[ "$output" == *"Not merged: vendor/b"* ]]
  [[ "$output" != *"working tree has modifications"* ]]
}

@test "pull: two subtrees sharing a remote URL -- one's push is pulled into the other" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  echo "a change" >>vendor/a/file.txt
  git add vendor/a
  git commit -q -m "change a"
  push_one "vendor/a" "main"
  fetch_one "vendor/b"

  classify_subtree "vendor/b" "main"
  [ "$SUBTREE_STATE" = "pull" ]

  run pull_one "vendor/b" "main"
  [ "$status" -eq 0 ]
  run grep -qx "a change" vendor/b/file.txt
  [ "$status" -eq 0 ]
}
