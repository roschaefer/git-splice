setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  local scenario
  for scenario in up-to-date push-ahead pull-ahead diverged-common-ancestor \
    diverged-unrelated-history never-fetched feature-branch-unchanged \
    feature-branch-changed diverged-then-pulled pushed-then-changed \
    squash-merged-pull merge-in-monorepo default-branch init-new-upstream \
    uncommitted-changes; do
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

@test "status: counts what push would publish and pull would bring in" {
  scenario_push_ahead "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "second local change"
  cd "$monorepo"
  run cmd_status
  [ "$output" = "ok   vendor/a -> main (push: ahead 2)" ]

  scenario_pull_ahead "$BATS_TEST_TMPDIR/pull" "$BATS_TEST_TMPDIR/pull.git"
  cd "$BATS_TEST_TMPDIR/pull"
  run cmd_status
  [ "$output" = "ok   vendor/a -> main (pull: behind 1)" ]

  scenario_diverged_common_ancestor "$BATS_TEST_TMPDIR/diverged" "$BATS_TEST_TMPDIR/diverged.git"
  cd "$BATS_TEST_TMPDIR/diverged"
  run cmd_status
  [ "$output" = "ok   vendor/a -> main (diverged: ahead 1, behind 1)" ]
}

@test "status: leaves the file summary to diff --stat" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" != *"file.txt"* ]]
}

@test "status: names upstream's branch when it differs" {
  scenario_default_branch "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [[ "${lines[0]}" == "ok   vendor/a -> master (push: ahead 1)" ]]
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
  [[ "${lines[0]}" == *"(upstream has no such branch; ahead 1 since 'main' -- push would create it)" ]]
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


@test "status: warns about uncommitted changes in a splice's folder" {
  scenario_uncommitted_changes "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "ok   vendor/a -> main (push: ahead 1)" ]]
  [[ "${lines[-1]}" == "??   vendor/a has uncommitted changes -- push only sends committed ones" ]]
}

@test "status: counts staged, unstaged and untracked files as uncommitted" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  echo staged >>vendor/a/file.txt
  git add vendor/a/file.txt
  run cmd_status
  [[ "$output" == *"vendor/a has uncommitted changes"* ]]
  git reset -q --hard
  echo unstaged >>vendor/a/file.txt
  run cmd_status
  [[ "$output" == *"vendor/a has uncommitted changes"* ]]
  git reset -q --hard
  echo untracked >vendor/a/new.txt
  run cmd_status
  [[ "$output" == *"vendor/a has uncommitted changes"* ]]
}

@test "status: doesn't count changes outside the splice or ignored files" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  echo outside >outside.txt
  echo 'vendor/a/build/' >.git/info/exclude
  mkdir vendor/a/build
  echo ignored >vendor/a/build/out.txt
  run cmd_status
  [ "$output" = "ok   vendor/a -> main (up to date)" ]
}

@test "status: says so when it can't check for uncommitted changes" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  # An invalid value that only git status reads makes it fail.
  git config status.relativePaths bogus
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "ok   vendor/a -> main (up to date)" ]]
  [[ "${lines[1]}" == "??   vendor/a: could not check for uncommitted changes (git status failed)" ]]
}

@test "status: a missing branch counts every commit the push creating it would publish" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "another change"
  cd "$monorepo"
  run cmd_status
  [[ "${lines[0]}" == *"(upstream has no such branch; ahead 2 since 'main' -- push would create it)" ]]
}

@test "status: a missing branch with no new commits for upstream says changed, not ahead 0" {
  load 'scenarios/clone-on-feature-branch/setup'
  scenario_clone_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"
  splice clone "$upstream" vendor/a >/dev/null
  run cmd_status
  [[ "${lines[0]}" == *"(upstream has no such branch; changed since 'main' -- push would create it)" ]]
}

@test "status: shows the state without counts if they can't be counted" {
  scenario_uncommitted_changes "$monorepo" "$upstream"
  cd "$monorepo"
  git() {
    [[ "$1 $2" == "rev-list --left-right" ]] && return 1
    command git "$@"
  }
  run cmd_status
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ok   vendor/a -> main (push)" ]
  [[ "${lines[1]}" == "??   vendor/a has uncommitted changes"* ]]
}
