setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load 'scenarios/01-everyday-sync/02-up-to-date/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/01-pull-ahead/setup'
  load 'scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/setup'
  load 'scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/01-feature-branch-changed/setup'
  load 'scenarios/04-upstreams/03-shared-remote-url/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "diff: shows the patch that would be pushed, with upstream's paths" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run splice diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"===  vendor/a"* ]]
  [[ "$output" == *"--- a/file.txt"* ]]
  [[ "$output" == *"+local change"* ]]
  [[ "$output" != *".splice"* ]]
}

@test "diff: prints nothing for a splice with nothing to push" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice diff
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "diff: does not show upstream-only changes" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run splice diff
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "diff: a missing upstream branch shows the commits no upstream branch has" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run splice diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"+local change"* ]]
  [[ "$output" != *"+seed"* ]]
}

@test "diff: a missing upstream branch a PR from which would show no changes shows nothing, though its commits are new" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  git -C "$monorepo" revert --no-edit HEAD >/dev/null
  cd "$monorepo"
  run splice diff
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "diff: without upstream's default branch, a missing upstream branch shows everything as new" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q main
  git update-ref -d "$(upstream_refs "$upstream")main"
  seed_bare_repo "$upstream" "elsewhere" other
  fetch_splice "$monorepo" "$upstream" vendor/a
  git -C "$upstream" branch -D main >/dev/null
  fetch_splice "$monorepo" "$upstream" vendor/a
  run splice diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"+seed"* ]]
}

@test "diff: a missing upstream branch shows commits from the branch it was cut from that upstream lacks" {
  load 'scenarios/03-branches-and-teamwork/02-feature-branch-from-main/setup'
  scenario_feature_branch_from_main "$monorepo" "$upstream"
  cd "$monorepo"
  run splice diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"+local change"* ]]
  [[ "$output" != *"+seed"* ]]
}

@test "diff: a missing upstream branch shows everything when upstream has none of its commits" {
  load 'scenarios/02-starting-a-splice/04-init-new-upstream/setup'
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  splice init lib/a "$upstream" >/dev/null
  run splice diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"new file mode"* ]]
}

@test "diff: path arguments restrict output" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  commit_local "$monorepo" "vendor/a" "change in a"
  commit_local "$monorepo" "vendor/b" "change in b"
  run splice diff vendor/b
  [[ "$output" == *"===  vendor/b"* ]]
  [[ "$output" != *"vendor/a"* ]]
}

@test "diff: redirected output does not invoke the pager" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"

  run env GIT_PAGER=false "$BATS_TEST_DIRNAME/../git-splice" diff

  [ "$status" -eq 0 ]
  [[ "$output" == *"+local change"* ]]
  [[ "$output" != *$'\033['* ]]
}

# Runs `git splice diff` in a terminal, the only place it pages, with
# shell code $1 run first.
diff_in_terminal() {
  script --version 2>/dev/null | grep -q util-linux || skip "no util-linux script to run diff in a terminal"
  TERM=xterm run script -qec "${1:-:}; exec '$BATS_TEST_DIRNAME/../git-splice' diff" /dev/null
}

@test "diff: output is colored while a pager is active" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config pager.splice 'sed s/^/paged:/'

  diff_in_terminal

  [ "$status" -eq 0 ]
  [[ "$output" == *"paged:"* ]]
  [[ "$output" == *$'\033['* ]]
}

@test "diff: quitting the pager early does not report a splice failure" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  seq 1 200000 >vendor/a/long.txt
  git add vendor/a/long.txt
  git commit -q -m "a diff longer than a pipe holds"
  git config pager.splice 'head -n 1'

  diff_in_terminal

  [ "$status" -eq 0 ]
  [[ "$output" != *"Failed:"* ]]
}

@test "diff: pager.splice=false overrides an exported pager" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config pager.splice false

  GIT_PAGER='missing-pager' diff_in_terminal

  [ "$status" -eq 0 ]
  [[ "$output" == *"file.txt"* ]]
}

@test "diff: an empty pager.splice value disables paging" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config pager.splice ""

  GIT_PAGER='missing-pager' diff_in_terminal

  [ "$status" -eq 0 ]
  [[ "$output" == *"file.txt"* ]]
}

@test "diff: a nonzero integer pager.splice value enables paging" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config pager.splice 2

  GIT_PAGER='sed s/^/paged:/' diff_in_terminal

  [ "$status" -eq 0 ]
  [[ "$output" == *"paged:"* ]]
}

@test "diff: git --no-pager overrides pager.splice" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config pager.splice 'missing-pager'

  GIT_PAGER=cat diff_in_terminal

  [ "$status" -eq 0 ]
  [[ "$output" == *"file.txt"* ]]
}

@test "diff: pager startup failure is returned even when SIGPIPE is ignored" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config pager.splice 'missing-pager-command'

  diff_in_terminal "trap '' PIPE"

  [ "$status" -ne 0 ]
  [[ "$output" == *"missing-pager-command"* ]]
}

@test "diff: pager startup failure is returned" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config pager.splice 'missing-pager-command'

  diff_in_terminal

  [ "$status" -ne 0 ]
  [[ "$output" == *"missing-pager-command"* ]]
}

@test "diff: --stat summarizes the changes per file instead of the patch" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run splice diff --stat
  [ "$status" -eq 0 ]
  [[ "$output" == *"file.txt | 1 +"* ]]
  [[ "$output" != *"+local change"* ]]
}

@test "diff: refuses git diff's other options" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run splice diff --name-only
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option: --name-only"* ]]
}

@test "diff: a path after -- that looks like an option is still a path" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run splice diff --stat -- --stat
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a splice: --stat"* ]]
}
