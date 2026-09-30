setup() {
  load 'helpers/fixtures'
  load_lib
  load 'scenarios/init-unrelated-content/setup'
  load 'scenarios/init-on-feature-branch/setup'
  load 'scenarios/init-copied-content/setup'
  load 'scenarios/init-without-commits/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "init: refuses a path nested inside an existing subtree, without registering a remote" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  cd "$monorepo"

  run cmd_init "vendor/a/extra" "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nested subtrees are not supported: 'vendor/a' and 'vendor/a/extra' overlap"* ]]
  run git remote get-url vendor/a/extra
  [ "$status" -ne 0 ]
}

@test "init: refuses a path containing an existing subtree, without registering a remote" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  cd "$monorepo"

  run cmd_init "vendor" "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nested subtrees are not supported: 'vendor' and 'vendor/a' overlap"* ]]
  run git remote get-url vendor
  [ "$status" -ne 0 ]
}

@test "init: adds a fresh empty path" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [ -f vendor/a/file.txt ]
  run git remote get-url vendor/a
  [ "$output" = "$upstream" ]
}

@test "init: -- reaches a path named like a flag, but git-subtree still can't use it" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"

  run cmd_init -- -h "$upstream"

  [ "$status" -eq 1 ]
  [[ "$output" == *"git-subtree cannot use a name starting with '-'"* ]]
  run git remote get-url -- -h
  [ "$status" -eq 2 ]
}

@test "init: refuses when the current branch name starts with '-', without registering a remote" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git symbolic-ref HEAD refs/heads/-weird

  run cmd_init "vendor/a" "$upstream"

  [ "$status" -eq 1 ]
  [[ "$output" == *"git-subtree cannot use a branch name starting with '-'"* ]]
  run git remote get-url vendor/a
  [ "$status" -eq 2 ]
}

@test "init: refuses a monorepo without commits, without registering a remote" {
  scenario_init_without_commits "$monorepo" "$upstream"
  cd "$monorepo"

  run cmd_init "vendor/a" "$upstream"

  [ "$status" -eq 1 ]
  [[ "$output" == *"branch 'main' has no commits yet -- create one and re-run: git commit --allow-empty -m 'initial commit'"* ]]
  [[ "$output" != *"working tree has modifications"* ]]
  run git remote get-url vendor/a
  [ "$status" -eq 2 ]
}

@test "init: adds the subtree once the monorepo has its first commit" {
  scenario_init_without_commits "$monorepo" "$upstream"
  cd "$monorepo"
  git commit -q --allow-empty -m "initial commit"

  run cmd_init "vendor/a" "$upstream"

  [ "$status" -eq 0 ]
  [ -f vendor/a/file.txt ]
}

@test "init: refuses when remote exists pointing elsewhere" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git remote add vendor/a "/some/other/url"

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already registered"* ]]
}

@test "init: no-op when already initialized" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_subtree "$monorepo" "$upstream" "vendor/a"
  cd "$monorepo"

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already initialized"* ]]
}

@test "init: refuses unrelated pre-existing content with move-aside guidance" {
  scenario_init_unrelated_content "$monorepo" "$upstream"
  cd "$monorepo"

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"move it aside"* ]]
  [[ "$output" == *"mv vendor/a vendor/a.bak"* ]]
}

@test "init: fails on a genuine fetch failure, distinct from a missing branch" {
  init_monorepo "$monorepo"
  cd "$monorepo"

  run cmd_init "vendor/a" "$BATS_TEST_TMPDIR/missing.git"

  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: fetch failed"* ]]
  [[ "$output" != *"nothing to add"* ]]
}

@test "init: no-op when remote lacks the current branch and no base branch resolves" {
  hermetic_git_config
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git checkout -q -b feature

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to add (pass --base <branch>"* ]]
  [[ "$output" != *"fetch failed"* ]]
  [[ "$output" != *"couldn't find remote ref"* ]]
  [ ! -e vendor/a ]
}

@test "init: exact branch probe does not match branch-name suffixes" {
  hermetic_git_config
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "team feature" "team/feature"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git checkout -q -b feature

  run cmd_init "vendor/a" "$upstream"

  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to add"* ]]
  [[ "$output" != *"fetch failed"* ]]
  [[ "$output" != *"couldn't find remote ref"* ]]
}

@test "init: on a branch the remote lacks, adds the remote's base branch" {
  hermetic_git_config
  scenario_init_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"using its 'main' branch; your first push creates 'feature'"* ]]
  run grep -qx "seed" vendor/a/file.txt
  [ "$status" -eq 0 ]
  run git -C "$upstream" rev-parse --verify --quiet refs/heads/feature
  [ "$status" -ne 0 ]

  classify_subtree "vendor/a" "feature"
  [ "$SUBTREE_STATE" = "missing-at-head" ]
  changes_vs_base "vendor/a"
  [ "$SUBTREE_CHANGES_VS_BASE" = "yes" ]
}

@test "init: after adding from the base branch, the first push creates the branch on top of it" {
  hermetic_git_config
  scenario_init_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_init "vendor/a" "$upstream"
  echo "feature change" >>vendor/a/file.txt
  git commit -q -am "feature change"

  run push_one "vendor/a" "feature"
  [ "$status" -eq 0 ]
  git -C "$upstream" merge-base --is-ancestor main feature
  run git -C "$upstream" show feature:file.txt
  [[ "$output" == *"feature change"* ]]
}

@test "init: --base names the base branch when nothing else resolves" {
  hermetic_git_config
  scenario_init_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"
  git config --unset init.defaultBranch

  run cmd_init --base main "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"using its 'main' branch"* ]]
  [ -f vendor/a/file.txt ]
}

@test "init: only registers the remote when it lacks the base branch too" {
  hermetic_git_config
  make_bare_repo "$upstream"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config init.defaultBranch main
  git checkout -q -b feature

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"remote has no 'feature' branch yet -- nothing to add"* ]]
  [ ! -e vendor/a ]
  run git remote get-url vendor/a
  [ "$output" = "$upstream" ]
}

@test "init: rejects more than one path/url pair" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  run cmd_init "vendor/a" "$upstream" "extra"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: git subtrees init"* ]]
}

@test "init: --base with another remote's tracking branch fetches the plain branch name" {
  hermetic_git_config
  scenario_init_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"
  git config --unset init.defaultBranch
  git remote add team/upstream "$BATS_TEST_TMPDIR/unused.git"
  git update-ref refs/remotes/team/upstream/main main

  run cmd_init --base team/upstream/main "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"using its 'main' branch"* ]]
  [ -f vendor/a/file.txt ]
}

@test "init: --base origin/HEAD follows the symbolic ref to its branch" {
  hermetic_git_config
  scenario_init_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"
  git config --unset init.defaultBranch
  git remote add origin "$BATS_TEST_TMPDIR/unused.git"
  git update-ref refs/remotes/origin/main main
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

  run cmd_init --base origin/HEAD "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"using its 'main' branch"* ]]
  [ -f vendor/a/file.txt ]
}

@test "init: the move-aside retry command keeps --base" {
  hermetic_git_config
  scenario_init_unrelated_content "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q -b feature

  run cmd_init --base main "vendor/a" "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git subtrees init --base main vendor/a $upstream"* ]]
}

@test "init: drops a stale tracking ref for a branch the remote no longer has" {
  hermetic_git_config
  scenario_init_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"
  # Left over from an earlier fetch of a remote 'feature' that is gone now.
  git remote add vendor/a "$upstream"
  git fetch -q vendor/a
  git update-ref refs/remotes/vendor/a/feature refs/remotes/vendor/a/main

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"using its 'main' branch"* ]]
  run git rev-parse --verify --quiet refs/remotes/vendor/a/feature
  [ "$status" -ne 0 ]
  classify_subtree "vendor/a" "feature"
  [ "$SUBTREE_STATE" = "missing-at-head" ]
}

@test "init: a base branch git-subtree can't use is an error, not 'nothing to add'" {
  hermetic_git_config
  scenario_init_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"
  git update-ref refs/heads/-base main

  run cmd_init --base refs/heads/-base "vendor/a" "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"-base: git-subtree cannot use a branch name starting with '-'"* ]]
  [[ "$output" != *"nothing to add"* ]]
}

@test "init: an explicit --base that doesn't resolve is an error" {
  hermetic_git_config
  scenario_init_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"

  run cmd_init --base mian "vendor/a" "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: base branch 'mian' not found, or it shares no history with 'feature'"* ]]
  [[ "$output" != *"nothing to add"* ]]
  [ ! -e vendor/a ]
}

@test "init: records the sync point for a folder copied in with the remote's content" {
  hermetic_git_config
  scenario_init_copied_content "$monorepo" "$upstream"
  cd "$monorepo"
  local tree_before
  tree_before="$(git rev-parse 'HEAD^{tree}')"

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"content matches 'main' on the remote -- recorded it as the last sync"* ]]
  [ "$(git rev-parse 'HEAD^{tree}')" = "$tree_before" ]
  [ -z "$(git status --porcelain)" ]

  local sync
  sync="$(find_sync_commit vendor/a)"
  [ -n "$sync" ]
  [ "$(sync_split_sha "$sync")" = "$(git -C "$upstream" rev-parse main)" ]
  classify_subtree "vendor/a" "main"
  [ "$SUBTREE_STATE" = "up-to-date" ]
}

@test "init: a second run on an adopted folder changes nothing" {
  hermetic_git_config
  scenario_init_copied_content "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_init "vendor/a" "$upstream"
  local head
  head="$(git rev-parse HEAD)"

  run cmd_init "vendor/a" "$upstream"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already initialized"* ]]
  [ "$(git rev-parse HEAD)" = "$head" ]
}

@test "init: after adopting a copied folder, a new remote branch builds on the remote's history" {
  hermetic_git_config
  scenario_init_copied_content "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_init "vendor/a" "$upstream"
  git checkout -q -b feature
  echo "feature change" >>vendor/a/file.txt
  git commit -q -am "feature change"

  run push_one "vendor/a" "feature" "main"
  [ "$status" -eq 0 ]
  git -C "$upstream" merge-base --is-ancestor main feature
}

@test "init: the first push after adopting a folder doesn't publish the folder's earlier history" {
  hermetic_git_config
  scenario_init_copied_content "$monorepo" "$upstream"
  cd "$monorepo"
  echo "TOP SECRET" >vendor/a/secret.txt
  git add vendor/a/secret.txt
  git commit -q -m "oops, a secret"
  local secret
  secret="$(git rev-parse HEAD:vendor/a/secret.txt)"
  git rm -q vendor/a/secret.txt
  git commit -q -m "remove the secret again"

  cmd_init "vendor/a" "$upstream"
  git checkout -q -b feature
  echo "feature change" >>vendor/a/file.txt
  git commit -q -am "feature change"
  run push_one "vendor/a" "feature" "main"
  [ "$status" -eq 0 ]

  run git -C "$upstream" cat-file -e "$secret"
  [ "$status" -ne 0 ]
  [ "$(git -C "$upstream" log --format=%s feature)" = $'feature change\nseed' ]
}
