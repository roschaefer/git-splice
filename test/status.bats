setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  local scenario
  for scenario in \
    01-everyday-sync/02-up-to-date \
    01-everyday-sync/02-up-to-date/02-push-ahead \
    01-everyday-sync/02-up-to-date/01-pull-ahead \
    01-everyday-sync/02-up-to-date/02-push-ahead/03-diverged-common-ancestor \
    06-rewritten-history/03-diverged-unrelated-history \
    01-everyday-sync/04-never-fetched \
    03-branches-and-teamwork/01-feature-branch-unchanged \
    03-branches-and-teamwork/01-feature-branch-unchanged/01-feature-branch-changed \
    01-everyday-sync/02-up-to-date/03-diverged-then-pulled \
    01-everyday-sync/02-up-to-date/02-push-ahead/01-pushed-then-pulled/01-pushed-then-changed \
    03-branches-and-teamwork/03-squash-merged-pull \
    03-branches-and-teamwork/01-feature-branch-unchanged/02-merge-in-monorepo \
    04-upstreams/01-default-branch \
    04-upstreams/03-shared-remote-url \
    02-starting-a-splice/04-init-new-upstream \
    01-everyday-sync/02-up-to-date/02-push-ahead/02-uncommitted-changes \
    05-nested-splices/01-nested-splices \
    03-branches-and-teamwork/06-teammate-pulled; do
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
@test "classify_splice: missing-synced after a teammate's pull that wasn't fetched" { assert_state teammate-pulled missing-synced; }

@test "classify_splice: up-to-date once a teammate's pull is fetched" {
  scenario_teammate_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  splice fetch vendor/a >/dev/null 2>&1
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = up-to-date ]
}
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
  [ "$output" = "$(printf 'On branch main\n\n  ahead 2  vendor/a')" ]

  scenario_pull_ahead "$BATS_TEST_TMPDIR/pull" "$BATS_TEST_TMPDIR/pull.git"
  cd "$BATS_TEST_TMPDIR/pull"
  run cmd_status
  [ "${lines[1]}" = "  behind 1  vendor/a" ]

  scenario_diverged_common_ancestor "$BATS_TEST_TMPDIR/diverged" "$BATS_TEST_TMPDIR/diverged.git"
  cd "$BATS_TEST_TMPDIR/diverged"
  run cmd_status
  [ "${lines[1]}" = "  ahead 1, behind 1  vendor/a" ]
}

@test "status: leaves the file summary to diff --stat" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" != *"file.txt"* ]]
}

@test "status: names upstream's branch when it differs" {
  scenario_default_branch "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [ "${lines[0]}" = "On branch main" ]
  [ "${lines[1]}" = "  ahead 1  vendor/a -> master" ]
}

@test "status: covers every splice by default and takes paths" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [ "${#lines[@]}" -eq 3 ]
  run cmd_status vendor/b
  [ "${lines[*]:1}" = "  up to date  vendor/b" ]
}

@test "status: missing branch, unchanged and changed" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [ "$output" = "$(cat <<'EOF'
On branch feature

  new, ahead 1  vendor/a  push creates the branch
EOF
  )" ]
  git checkout -q -b other main
  run cmd_status
  [ "$output" = "$(cat <<'EOF'
On branch other

  unchanged, no upstream branch  vendor/a
EOF
  )" ]
}

@test "status: a missing branch is new with commits from the branch it was cut from that upstream lacks" {
  load 'scenarios/03-branches-and-teamwork/02-feature-branch-from-main/setup'
  scenario_feature_branch_from_main "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [ "${lines[1]}" = "  new, ahead 1  vendor/a  push creates the branch" ]
}

@test "status: a missing branch also counts the commits upstream's default branch has and it lacks, as a PR would" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  fetch_splice "$monorepo" "$upstream" vendor/a
  cd "$monorepo"
  run cmd_status
  [ "${lines[1]}" = "  new, ahead 1, behind 1  vendor/a  push creates the branch" ]
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
  [ "${lines[1]}" = "  ahead 1  vendor/a  uncommitted changes" ]
}

@test "status: counts staged, unstaged and untracked files as uncommitted" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  echo staged >>vendor/a/file.txt
  git add vendor/a/file.txt
  run cmd_status
  [[ "$output" == *"vendor/a  uncommitted changes"* ]]
  git reset -q --hard
  echo unstaged >>vendor/a/file.txt
  run cmd_status
  [[ "$output" == *"vendor/a  uncommitted changes"* ]]
  git reset -q --hard
  echo untracked >vendor/a/new.txt
  run cmd_status
  [[ "$output" == *"vendor/a  uncommitted changes"* ]]
}

@test "status: doesn't count changes outside the splice or ignored files" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  echo outside >outside.txt
  echo 'vendor/a/build/' >.git/info/exclude
  mkdir vendor/a/build
  echo ignored >vendor/a/build/out.txt
  run cmd_status
  [ "${lines[*]:1}" = "  up to date  vendor/a" ]
}

@test "status: counts uncommitted changes only for the splice they're in" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  echo changed >>vendor/b/file.txt
  run cmd_status
  [[ "$output" == *"vendor/b  uncommitted changes"* ]]
  [[ "$output" != *"vendor/a  uncommitted changes"* ]]
}

@test "status: an untracked folder in a splice below another counts for both" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir vendor/a/b/new
  echo x >vendor/a/b/new/file.txt
  run cmd_status
  [[ "$output" == *"vendor/a  "*"uncommitted changes"* ]]
  [[ "$output" == *"vendor/a/b  "*"uncommitted changes"* ]]
}

@test "status: the real command lists uncommitted changes in a splice other than the last one" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  echo changed >>vendor/a/file.txt
  run splice status
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a  uncommitted changes"* ]]
}

@test "status: asks git status once for all splices" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  echo changed >>vendor/b/file.txt
  git() {
    [[ "$1" != status ]] || echo status >>"$BATS_TEST_TMPDIR/calls"
    command git "$@"
  }
  run cmd_status
  [ "$status" -eq 0 ]
  [ "$(grep -c status "$BATS_TEST_TMPDIR/calls")" -eq 1 ]
}

@test "status: says so when it can't check for uncommitted changes" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  # An invalid value that only git status reads makes it fail.
  git config status.relativePaths bogus
  run cmd_status
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "  up to date  vendor/a  could not check for uncommitted changes (git status failed)" ]
}

@test "status: a missing branch counts every commit the push creating it would publish" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "another change"
  cd "$monorepo"
  run cmd_status
  [ "${lines[1]}" = "  new, ahead 2  vendor/a  push creates the branch" ]
}

@test "status: a missing branch is unchanged right after cloning on a feature branch: upstream has every commit" {
  load 'scenarios/02-starting-a-splice/03-clone-on-feature-branch/setup'
  scenario_clone_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"
  splice clone "$upstream" vendor/a >/dev/null
  run cmd_status
  [ "${lines[1]}" = "  unchanged, no upstream branch  vendor/a" ]
}

@test "status: a missing branch is unchanged when a PR from it would show no changes, though its commits are new: a change and its revert" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  git -C "$monorepo" revert --no-edit HEAD >/dev/null
  cd "$monorepo"
  run cmd_status
  [ "${lines[1]}" = "  unchanged, no upstream branch  vendor/a" ]
}

@test "status: a missing branch with a change and its revert stays unchanged after upstream's default branch moves on" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  git -C "$monorepo" revert --no-edit HEAD >/dev/null
  seed_bare_repo "$upstream" "upstream change"
  fetch_splice "$monorepo" "$upstream" vendor/a
  cd "$monorepo"
  run cmd_status
  [ "${lines[1]}" = "  unchanged, no upstream branch  vendor/a" ]
}

@test "status: a missing branch that can't be rebuilt warns, without the rebuild's error" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  rebuild_splice() { die "vendor/a: synced commit isn't available locally"; }
  run cmd_status
  [ "$status" -eq 0 ]
  [ "${lines[*]:1}" = "  ?? no upstream branch  vendor/a  could not compare with upstream's 'main'" ]
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
  [ "${lines[1]}" = "  ahead  vendor/a  uncommitted changes" ]
}

@test "status: a missing branch counts the commits the push creating it would publish" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  splice init lib/a "$upstream" >/dev/null
  run cmd_status
  [ "$output" = "$(printf 'On branch main\n\n  new, ahead 1  lib/a  push creates the branch')" ]
}

@test "status: a splice moved with git mv still finds its fetched refs" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir libs && git mv vendor/a libs/a && git commit -q -m "move a"
  run cmd_status
  [ "${lines[1]}" = "  ahead 1  libs/a" ]
}

@test "status: splices at one path with different upstreams on two branches keep their own refs" {
  scenario_up_to_date "$monorepo" "$upstream"
  local other="$BATS_TEST_TMPDIR/other.git"
  make_bare_repo "$other"
  seed_bare_repo "$other" "other seed" release
  cd "$monorepo"
  git checkout -q -b release
  git rm -q -r vendor/a && git commit -q -m "remove vendor/a"
  add_splice "$monorepo" "$other" vendor/a release
  seed_bare_repo "$other" "colleague's change" release

  splice fetch >/dev/null
  run cmd_status
  [ "${lines[1]}" = "  behind 1  vendor/a" ]

  git checkout -q main
  splice fetch >/dev/null
  git checkout -q release
  run cmd_status
  [ "${lines[1]}" = "  behind 1  vendor/a" ]
}

@test "status: lists the splices that need something first, most urgent first, then the quiet ones" {
  load 'scenarios/01-everyday-sync/03-many-splices/setup'
  scenario_many_splices "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_status
  [ "$output" = "$(cat <<'EOF2'
On branch main

  ahead 1, behind 1  libs/store
  behind 2           libs/http
  ahead 1            libs/parser

  up to date         libs/cli
  up to date         libs/theme -> master
EOF2
  )" ]
}

@test "status: a quiet splice with uncommitted changes moves up" {
  load 'scenarios/01-everyday-sync/03-many-splices/setup'
  scenario_many_splices "$monorepo" "$upstream"
  cd "$monorepo"
  echo "work in progress" >>libs/cli/file.txt
  run cmd_status
  [ "${lines[4]}" = "  up to date         libs/cli  uncommitted changes" ]
  [ "${lines[5]}" = "  up to date         libs/theme -> master" ]
}

@test "status: without a splice that needs something, prints no blank line between groups" {
  load 'scenarios/01-everyday-sync/03-many-splices/setup'
  scenario_many_splices "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q -b feature
  run cmd_status libs/cli libs/http libs/theme
  [ "$output" = "$(cat <<'EOF2'
On branch feature

  unchanged, no upstream branch  libs/cli
  unchanged, no upstream branch  libs/http
  unchanged, no upstream branch  libs/theme
EOF2
  )" ]
}

@test "status: dims the quiet splices where git status would be colored" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "local change"
  cd "$monorepo"
  run cmd_status
  [[ "$output" != *$'\e['* ]]
  git config color.status always
  run cmd_status
  [ "${lines[1]}" = "  ahead 1     vendor/a" ]
  [ "${lines[2]}" = $'\e[2m  up to date  vendor/b\e[m' ]
}

@test "status: dims the quiet splices in a terminal, with Git's default color.ui=auto" {
  script --version 2>/dev/null | grep -q util-linux || skip "no util-linux script to run status in a terminal"
  scenario_shared_remote_url "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "local change"
  cd "$monorepo"
  # Git colors no terminal without a TERM, or with TERM=dumb, and CI has none.
  TERM=xterm run script -qec "$BATS_TEST_DIRNAME/../git-splice status" /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[2m  up to date  vendor/b\e[m'* ]]
}
