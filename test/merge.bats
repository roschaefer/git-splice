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
  load 'scenarios/up-to-date/push-ahead/pushed-then-pulled/setup'
  load 'scenarios/up-to-date/push-ahead/pushed-then-pulled/pushed-then-changed/setup'
  load 'scenarios/init-new-upstream/setup'
  load 'scenarios/up-to-date/push-ahead/edited-before-push/setup'
  load 'scenarios/upstream-rewritten-equal-tree/setup'
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

@test "merge: an upstream rewritten to the same files becomes the synced commit, so a later change pushes on top of it" {
  scenario_upstream_rewritten_equal_tree "$monorepo" "$upstream"
  cd "$monorepo"
  local before target
  before="$(git rev-parse HEAD)"
  target="$(git rev-parse "$(upstream_refs "$upstream")main")"
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD^)" = "$before" ]
  [ "$(git diff --name-only HEAD^ HEAD)" = "vendor/a/.splice" ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
  commit_local "$monorepo" vendor/a "local change"
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = push ]
  [ "$(git rev-parse "$SPLICE_REBUILT^")" = "$target" ]
}

@test "merge: right after a push, nothing is recorded: the rebuild is the upstream branch" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: nothing to merge" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge --bump: right after a push, records the upstream branch, so the rebuild starts there" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  local before target
  before="$(git rev-parse HEAD)"
  target="$(git rev-parse "$(upstream_refs "$upstream")main")"
  run cmd_merge --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: bumped the synced commit to ${target:0:7}" ]
  [ "$(git rev-parse HEAD^)" = "$before" ]
  [ "$(git diff --name-only HEAD^ HEAD)" = "vendor/a/.splice" ]
  [ "$(git log -1 --format=%s)" = "splice: bump vendor/a from main at ${target:0:7}" ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
  [ "$(splice_boundary vendor/a HEAD)" = "$(git rev-parse HEAD)" ]
  [ "$(rebuild_splice vendor/a)" = "$target" ]
}

@test "merge --bump: a later push sends the same commit as without the bump" {
  # The commit is made twice, and both must get the same hash.
  export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z
  scenario_pushed_then_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local unbumped
  unbumped="$(rebuild_splice vendor/a)"
  git reset -q --hard HEAD^
  cmd_merge --bump vendor/a >/dev/null
  commit_local "$monorepo" vendor/a "later change"
  [ "$(rebuild_splice vendor/a)" = "$unbumped" ]
}

@test "merge --bump: while ahead, the unpushed commit stays in the rebuild" {
  scenario_pushed_then_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local before target
  before="$(rebuild_splice vendor/a)"
  target="$(git rev-parse "$(upstream_refs "$upstream")main")"
  run cmd_merge --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
  [ "$(rebuild_splice vendor/a)" = "$before" ]
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = push ]
}

@test "merge --bump: nothing to bump once the synced commit is the upstream branch" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_merge --bump vendor/a >/dev/null
  local before
  before="$(git rev-parse HEAD)"
  run cmd_merge --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: nothing to merge" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge --bump: never moves the synced commit back to a stale upstream ref" {
  scenario_pushed_then_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local ref synced before
  ref="$(upstream_refs "$upstream")main"
  cmd_merge --bump vendor/a >/dev/null
  synced="$(splice_config vendor/a commit)"
  git update-ref "$ref" "$synced^"
  before="$(git rev-parse HEAD)"
  run cmd_merge --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: nothing to bump -- the fetched 'main' is older than the synced commit" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge --bump: gives a splice that init made and push published its first synced commit" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  splice init lib/a "$upstream" >/dev/null 2>&1
  splice push lib/a >/dev/null 2>&1
  [ -z "$(splice_config lib/a commit)" ]
  run cmd_merge --bump lib/a
  [ "$status" -eq 0 ]
  [ "$(splice_config lib/a commit)" = "$(git -C "$upstream" rev-parse main)" ]
}

@test "merge: a push of an edited rebuild becomes the synced commit, so the original commit is never pushed" {
  scenario_edited_before_push "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt edited
  rebuilt="$(rebuild_splice vendor/a)"
  edited="$(git commit-tree "$rebuilt^{tree}" -p "$rebuilt^" -m "fix the parser")"
  git push -q "$upstream" "$edited:refs/heads/main"
  splice fetch >/dev/null
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a commit)" = "$edited" ]
  commit_local "$monorepo" vendor/a "another fix"
  splice push vendor/a >/dev/null
  [ "$(git -C "$upstream" log --format=%s main)" = "another fix"$'\n'"fix the parser"$'\n'"seed" ]
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

@test "pull --bump: fetches, then bumps" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_pull --bump vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: bumped the synced commit to"* ]]
  [ "$(splice_config vendor/a commit)" = "$(git -C "$upstream" rev-parse main)" ]
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
