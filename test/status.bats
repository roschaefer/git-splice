setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  local scenario
  for scenario in up-to-date push-ahead pull-ahead diverged-common-ancestor \
    diverged-unrelated-history never-fetched feature-branch-unchanged \
    feature-branch-changed diverged-then-pulled pushed-then-changed \
    squash-merged-pull merge-in-monorepo default-branch init-new-upstream; do
    load "scenarios/$scenario/setup"
  done
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

# Runs scenario $1, then checks that vendor/a classifies as state $2.
assert_state() {
  "scenario_${1//-/_}" "$monorepo" "$upstream"
  cd "$monorepo"
  classify_splice vendor/a "$(current_branch)"
  echo "state: $SPLICE_STATE" >&2
  [ "$SPLICE_STATE" = "$2" ]
}

@test "classify_splice: up-to-date" { assert_state up-to-date up-to-date; }
@test "classify_splice: push" { assert_state push-ahead push; }
@test "classify_splice: pull" { assert_state pull-ahead pull; }
@test "classify_splice: diverged" { assert_state diverged-common-ancestor diverged; }
@test "classify_splice: unrelated-history" { assert_state diverged-unrelated-history unrelated-history; }
@test "classify_splice: never-fetched" { assert_state never-fetched never-fetched; }
@test "classify_splice: missing-branch" { assert_state feature-branch-unchanged missing-branch; }
@test "classify_splice: push after pulling a divergence" { assert_state diverged-then-pulled push; }
@test "classify_splice: push after our own push and another local change" { assert_state pushed-then-changed push; }
@test "classify_splice: push after a pull on a squash-merged branch" { assert_state squash-merged-pull push; }
@test "classify_splice: missing-branch after a merge in the monorepo" { assert_state merge-in-monorepo missing-branch; }
@test "classify_splice: push on the default branch, synced with upstream's master" { assert_state default-branch push; }

@test "classify_splice: up-to-date after our own push" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  splice push vendor/a >/dev/null 2>&1
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = up-to-date ]
}

@test "classify_splice: push after our own push and its revert" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  splice push vendor/a >/dev/null 2>&1
  git revert --no-edit HEAD >/dev/null
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = push ]
}

@test "classify_splice: diverged when someone else committed on top of our push" {
  scenario_pushed_then_changed "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "someone else"
  fetch_splice "$monorepo" "$upstream" vendor/a
  cd "$monorepo"
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = diverged ]
}

@test "classify_splice: someone else's commit with our content isn't taken for our push" {
  scenario_push_ahead "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "local change"
  fetch_splice "$monorepo" "$upstream" vendor/a
  cd "$monorepo"
  classify_splice vendor/a main
  # Equal content: nothing to push or pull.
  [ "$SPLICE_STATE" = up-to-date ]
}

@test "classify_splice: missing-branch, not never-fetched, for an init'd splice whose upstream is empty" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  splice init lib/a "$upstream" >/dev/null
  classify_splice lib/a main
  [ "$SPLICE_STATE" = missing-branch ]
}

@test "status: prints each state" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "ok   vendor/a -> main (diverged)" ]]
  [[ "$output" == *"file.txt | 2 +-"* ]]
}

@test "status: names upstream's branch when it differs" {
  scenario_default_branch "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [[ "${lines[0]}" == "ok   vendor/a -> master (push)" ]]
}

@test "status: covers every splice by default and takes paths" {
  load 'scenarios/shared-remote-url/setup'
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [ "${#lines[@]}" -eq 2 ]
  run cmd_status vendor/b
  [ "$output" = "ok   vendor/b -> main (up to date)" ]
}

@test "status: missing branch, unchanged and changed" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [[ "${lines[0]}" == *"(upstream has no such branch; changed since 'main' -- push would create it)" ]]
  [[ "$output" == *"file.txt | 1 +"* ]]
  git checkout -q -b other main
  run cmd_status
  [[ "$output" == *"(upstream has no such branch; unchanged since 'main')" ]]
}

@test "status: says how to start without splices" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  run cmd_status
  [[ "$output" == *"no splices"* ]]
}

@test "classify_splice: missing-branch, not never-fetched, after upstream deleted its last branch" {
  scenario_push_ahead "$monorepo" "$upstream"
  git -C "$upstream" symbolic-ref HEAD refs/heads/gone
  git -C "$upstream" branch -D main >/dev/null
  cd "$monorepo"
  splice fetch vendor/a >/dev/null
  [ -z "$(git for-each-ref refs/splices/)" ]
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = missing-branch ]
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "local change" ]
}

