setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/up-to-date/setup'
  load 'scenarios/up-to-date/push-ahead/setup'
  load 'scenarios/up-to-date/pull-ahead/setup'
  load 'scenarios/up-to-date/push-ahead/diverged-common-ancestor/setup'
  load 'scenarios/up-to-date/push-ahead/diverged-unrelated-history/setup'
  load 'scenarios/never-fetched/setup'
  load 'scenarios/up-to-date/shared-remote-url/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "merge: adds exactly one first-parent commit and no upstream ancestors" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD^)" = "$before" ]
  [ "$(git rev-list --parents -1 HEAD | wc -w)" -eq 2 ]
  ! git merge-base --is-ancestor "$(upstream_refs "$upstream")main" HEAD
  [ "$(git log -1 --format=%s)" = "splice: merge vendor/a from main at $(git rev-parse --short=7 "$(upstream_refs "$upstream")main")" ]
}

@test "merge: brings upstream's content and records the synced commit" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_merge vendor/a
  [ "$(git rev-parse HEAD:vendor/a/file.txt)" = "$(git rev-parse "$(upstream_refs "$upstream")main":file.txt)" ]
  [ "$(splice_config vendor/a commit)" = "$(git rev-parse "$(upstream_refs "$upstream")main")" ]
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = up-to-date ]
}

@test "merge: keeps the splice's id" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local id
  id="$(splice_config vendor/a id)"
  cmd_merge vendor/a
  [ "$(splice_config vendor/a id)" = "$id" ]
}

@test "merge: refuses an upstream that brings in a .splice at its root" {
  scenario_pull_ahead "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "[splice]" main .splice
  cd "$monorepo"
  splice fetch vendor/a >/dev/null
  local before
  before="$(git rev-parse HEAD)"
  run cmd_merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"upstream has a .splice at its root, which would replace vendor/a/.splice"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge: keeps local changes when merging a divergence" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  # Make the two changes touch different files, so they merge cleanly.
  git reset -q --hard HEAD^
  commit_local "$monorepo" "vendor/a" "local change" local.txt
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/local.txt)" = "local change" ]
  grep -q "upstream change" vendor/a/file.txt
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = push ]
}

@test "merge: a conflict is resolved like any other, and git commit finishes it" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT"*"vendor/a/file.txt"* ]]
  [[ "$output" == *"resolve it, then 'git commit'"* ]]
  [ "$(git status --porcelain vendor/a/file.txt)" = "UU vendor/a/file.txt" ]
  printf 'seed\nboth\n' >vendor/a/file.txt
  git add vendor/a/file.txt
  git commit -q --no-edit
  [[ "$(git log -1 --format=%s)" == "splice: merge vendor/a from main at "* ]]
  [ "$(splice_config vendor/a commit)" = "$(git rev-parse "$(upstream_refs "$upstream")main")" ]
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = push ]
}

@test "merge: stops at a conflict and doesn't start the next splice" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  add_splice "$monorepo" "$upstream" vendor/b
  cd "$monorepo"
  run cmd_merge --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not merged yet: vendor/b"* ]]
}

@test "merge: nothing to do when up to date or only ahead" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to merge"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge: refuses to guess on unrelated history" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"share no history -- pick a side"* ]]
}

@test "merge: asks for a fetch first" {
  scenario_never_fetched "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"not fetched yet"* ]]
}

@test "merge: needs paths or --all" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge
  [ "$status" -eq 1 ]
  [[ "$output" == *"which splice?"* ]]
}

@test "merge: leaves the worktree's other changes alone" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  echo "work in progress" >wip.txt
  cmd_merge vendor/a
  [ "$(cat wip.txt)" = "work in progress" ]
  [ "$(git status --porcelain)" = "?? wip.txt" ]
}

@test "pull: fetches, then merges" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  cd "$monorepo"
  run cmd_pull vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a fetched (main moved"* ]]
  [[ "$output" == *"vendor/a: pulled"* ]]
  [ "$(git log -1 --format=%s)" = "splice: pull vendor/a from main at $(git rev-parse --short=7 "$(upstream_refs "$upstream")main")" ]
}

@test "pull: a failed fetch is reported, the rest still merges" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  cd "$monorepo"
  git config --file vendor/b/.splice upstream.origin.url "$BATS_TEST_TMPDIR/nowhere.git"
  git commit -q -am "break vendor/b"
  run cmd_pull --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: pulled"* ]]
  [[ "$output" == *"Not fetched: vendor/b"* ]]
}
