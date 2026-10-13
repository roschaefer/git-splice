setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  local scenario
  for scenario in \
    up-to-date \
    up-to-date/push-ahead \
    up-to-date/pull-ahead \
    up-to-date/push-ahead/diverged-common-ancestor \
    up-to-date/push-ahead/diverged-unrelated-history \
    never-fetched \
    up-to-date/feature-branch-unchanged \
    up-to-date/feature-branch-unchanged/feature-branch-changed \
    up-to-date/diverged-then-pulled \
    up-to-date/push-ahead/pushed-then-pulled/pushed-then-changed \
    up-to-date/shared-remote-url \
    default-branch \
    up-to-date/push-ahead/uncommitted-changes; do
    load "scenarios/$scenario/setup"
  done
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "push: publishes the rebuilt commits and updates the private ref" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a)"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: pushed ${rebuilt:0:7} to main"* ]]
  [ "$(git -C "$upstream" rev-parse main)" = "$rebuilt" ]
  [ "$(git rev-parse "$(upstream_refs "$upstream")main")" = "$rebuilt" ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "local change" ]
  ! git -C "$upstream" cat-file -e main:.splice 2>/dev/null
}

@test "push: writes nothing to the monorepo and creates no Git remote" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -z "$(git status --porcelain)" ]
  [ -z "$(git remote)" ]
}

@test "push: a plain git push has nowhere to send the monorepo" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config push.autoSetupRemote true
  git checkout -q -b topic
  run git push
  [ "$status" -ne 0 ]
  ! git -C "$upstream" rev-parse --verify --quiet topic
}

@test "push: then pushing again has nothing to do" {
  scenario_pushed_then_changed "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  run cmd_push vendor/a
  [[ "$output" == *"vendor/a: nothing to push"* ]]
}

@test "push: after pulling a divergence, sends the local commit and a merge" {
  scenario_diverged_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" rev-list --count --merges main)" -eq 1 ]
  git -C "$upstream" log --format=%s main | grep -qx "local change"
}

@test "push: refuses when upstream has commits this branch lacks" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"run 'git splice pull vendor/a' first"* ]]
}

@test "push: nothing to push when upstream is ahead" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"upstream is ahead"* ]]
}

@test "push: --force discards commits only upstream has" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push --force vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "seed" ]
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = up-to-date ]
}

@test "push: --force works after upstream lost the synced commit" {
  scenario_push_ahead "$monorepo" "$upstream"
  # Upstream is rebuilt from scratch, so the synced commit is gone for good,
  # as in a fresh clone of the monorepo.
  rm -rf "$upstream"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "brand new unrelated history"
  cd "$monorepo"
  git for-each-ref --format='delete %(refname)' refs/splices/ | git update-ref --stdin
  git reflog expire --expire=now --all && git gc -q --prune=now
  fetch_splice "$monorepo" "$upstream" vendor/a
  ! git cat-file -e "$(splice_config vendor/a commit)^{commit}" 2>/dev/null
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = unrelated-history ]
  run cmd_push --force vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "local change" ]
}

@test "push: refuses unrelated history, --force overwrites it" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"pick a side"* ]]
  run cmd_push --force vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "local change" ]
}

@test "push: asks for a fetch first" {
  scenario_never_fetched "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"not fetched"* ]]
}

@test "push: creates a missing upstream branch only if the splice changed" {
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [[ "$output" == *"nothing to push (upstream has no 'feature' branch; unchanged since 'main')"* ]]
  ! git -C "$upstream" rev-parse --verify --quiet feature
  commit_local "$monorepo" "vendor/a" "local change"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"this push creates it (changed since 'main')"* ]]
  [ "$(git -C "$upstream" log -1 --format=%s feature)" = "local change" ]
  [ "$(git -C "$upstream" rev-parse feature^)" = "$(git -C "$upstream" rev-parse main)" ]
}

@test "push: asks for --base when the base branch can't be found" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  git config --unset init.defaultBranch
  run cmd_push vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"re-run with --base <branch>"* ]]
  run cmd_push --base main vendor/a
  [ "$status" -eq 0 ]
}

@test "push: removes its SSH control folder and exits cleanly" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir "$BATS_TEST_TMPDIR/tmp"
  TMPDIR="$BATS_TEST_TMPDIR/tmp" run splice push vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: pushed $(git rev-parse --short=7 "$(upstream_refs "$upstream")main") to main" ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/tmp")" ]
}

@test "push: on the default branch, pushes to upstream's default branch" {
  scenario_default_branch "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"to master"* ]]
  [ "$(git -C "$upstream" log -1 --format=%s master)" = "local change" ]
  ! git -C "$upstream" rev-parse --verify --quiet main
}

@test "push: needs paths or --all, and pushes every changed splice with --all" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push
  [ "$status" -eq 1 ]
  commit_local "$monorepo" "vendor/b" "change in b"
  run cmd_push --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: nothing to push"* ]]
  [[ "$output" == *"vendor/b: pushed"* ]]
}

@test "push: warns about uncommitted changes and pushes only committed ones" {
  scenario_uncommitted_changes "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "??   vendor/a: uncommitted changes aren't pushed -- commit them first" ]]
  [[ "$output" == *"vendor/a: pushed"* ]]
  [ "$(git -C "$upstream" show main:file.txt)" = "$(git show HEAD:vendor/a/file.txt)" ]
}

@test "push: says so when it can't check for uncommitted changes" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  # An invalid value that only git status reads makes it fail.
  git config status.relativePaths bogus
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "??   vendor/a: could not check for uncommitted changes (git status failed) -- only committed ones are pushed" ]]
  [[ "$output" == *"vendor/a: pushed"* ]]
}

# Prints the rebuild of vendor/a with its last commit's message replaced
# by <message>, as an edit in a separate worktree would make it.
reworded_rebuild() {
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a)"
  git commit-tree --no-gpg-sign "$rebuilt^{tree}" -p "$rebuilt^" -m "$1"
}

@test "push --rebuilt-commit: pushes the given commit instead of the rebuild, e.g. with a reworded message, and asks for a pull before the next change" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local edited
  edited="$(reworded_rebuild "fix the parser")"
  run cmd_push --rebuilt-commit "$edited" vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' "ok   vendor/a: pushed ${edited:0:7} to main" "??   vendor/a: run 'git splice pull --bump vendor/a' before the next change to it -- that records ${edited:0:7} as the synced commit")" ]
  [ "$(git -C "$upstream" rev-parse main)" = "$edited" ]
  [ "$(git rev-parse "$(upstream_refs "$upstream")main")" = "$edited" ]
}

@test "push --rebuilt-commit: doesn't ask for a pull for the unchanged rebuild, which the monorepo builds on already" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a)"
  run cmd_push --rebuilt-commit "$rebuilt" vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: pushed ${rebuilt:0:7} to main" ]
  run cmd_pull vendor/a
  [ "$output" = "$(printf '%s\n' "ok   vendor/a fetched" "ok   vendor/a: nothing to pull")" ]
}

@test "push --rebuilt-commit: asks for pull --bump for an ancestor of the rebuild with its files, e.g. without a commit and its revert" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  commit_local "$monorepo" vendor/a "temporary" tmp.txt
  git rm -q vendor/a/tmp.txt && git commit -q -m "revert temporary"
  local edited
  edited="$(rebuild_splice vendor/a)~2"
  edited="$(git rev-parse "$edited")"
  run cmd_push --rebuilt-commit "$edited" vendor/a
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "??   vendor/a: run 'git splice pull --bump vendor/a' before the next change to it -- that records ${edited:0:7} as the synced commit" ]
  run cmd_pull --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a commit)" = "$edited" ]
  commit_local "$monorepo" vendor/a "next change"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log --format=%s main)" = "$(printf '%s\n' "next change" "local change" "seed")" ]
}

@test "push --force --rebuilt-commit: refuses a commit older than the synced commit, which nothing could record" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  seed_bare_repo "$upstream" "second"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" vendor/a
  cd "$monorepo"
  echo seed >vendor/a/file.txt && git commit -q -am "revert second"
  local synced
  synced="$(splice_config vendor/a commit)"
  run cmd_push --force --rebuilt-commit "$synced^" vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a: $(git rev-parse --short=7 "$synced^") is the synced commit ${synced:0:7} or older -- pull can't record it, and the next push would publish the commits after it again" ]
  [ "$(git -C "$upstream" rev-parse main)" = "$synced" ]
}

@test "push --rebuilt-commit: refuses the synced commit itself, e.g. without commits that cancel each other out" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  commit_local "$monorepo" vendor/a "temporary" tmp.txt
  git rm -q vendor/a/tmp.txt && git commit -q -m "revert temporary"
  local synced
  synced="$(splice_config vendor/a commit)"
  run cmd_push --rebuilt-commit "$synced" vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a: ${synced:0:7} is the synced commit ${synced:0:7} or older -- pull can't record it, and the next push would publish the commits after it again" ]
}

@test "push --force --rebuilt-commit: asks for a pull while the synced commit isn't here, even for the rebuild" {
  scenario_push_ahead "$monorepo" "$upstream"
  rm -rf "$upstream"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "brand new unrelated history"
  cd "$monorepo"
  git for-each-ref --format='delete %(refname)' refs/splices/ | git update-ref --stdin
  git reflog expire --expire=now --all && git gc -q --prune=now
  fetch_splice "$monorepo" "$upstream" vendor/a
  local rebuilt
  rebuilt="$(REBUILD_WITHOUT_SYNCED=1 rebuild_splice vendor/a)"
  run cmd_push --force --rebuilt-commit "$rebuilt" vendor/a
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "??   vendor/a: run 'git splice pull --bump vendor/a' before the next change to it -- that records ${rebuilt:0:7} as the synced commit" ]
}

@test "push --rebuilt-commit: replaces a published commit with a reworded one, with --force" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push vendor/a
  [ "$status" -eq 0 ]
  local published edited
  published="$(git -C "$upstream" rev-parse main)"
  edited="$(reworded_rebuild "fix the parser")"
  run cmd_push --rebuilt-commit "$edited" vendor/a
  [ "$status" -eq 1 ]
  [ "$(git -C "$upstream" rev-parse main)" = "$published" ]
  run cmd_push --force --rebuilt-commit "$edited" vendor/a
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ok   vendor/a: pushed ${edited:0:7} to main" ]
  [ "$(git -C "$upstream" rev-parse main)" = "$edited" ]
  run cmd_push --rebuilt-commit "$edited" vendor/a
  [ "$output" = "ok   vendor/a: nothing to push" ]
}

@test "push --rebuilt-commit: creates a missing upstream branch with the given commit" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local edited
  edited="$(reworded_rebuild "fix the parser")"
  run cmd_push --rebuilt-commit="$edited" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" rev-parse feature)" = "$edited" ]
}

@test "push --rebuilt-commit: refuses a commit with other files than the folder, which only a monorepo commit may change" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt other
  rebuilt="$(rebuild_splice vendor/a)"
  other="$(git commit-tree --no-gpg-sign "$(git rev-parse "$rebuilt^^{tree}")" -p "$rebuilt" -m "undo")"
  run cmd_push --rebuilt-commit "$other" vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a: ${other:0:7} has other files than the folder -- --rebuilt-commit only takes edits to the history; commit changes to files in the monorepo" ]
  [ "$(git -C "$upstream" rev-parse main)" = "$(splice_config vendor/a commit)" ]
}

@test "push --rebuilt-commit: refuses a commit that doesn't contain the synced commit, even where the upstream would take it" {
  scenario_feature_branch_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local root synced
  root="$(git commit-tree --no-gpg-sign "$(rebuild_splice vendor/a)^{tree}" -m "squashed")"
  synced="$(splice_config vendor/a commit)"
  run cmd_push --rebuilt-commit "$root" vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a: ${root:0:7} doesn't contain the synced commit ${synced:0:7} -- edit only the commits after it, or replace published ones with --force" ]
  ! git -C "$upstream" rev-parse --verify --quiet feature
}

# Like scenario_push_ahead, but the synced commit U ("second") has a
# parent ("seed"), so a commit before U can be edited.
scenario_push_ahead_after_two() {
  make_bare_repo "$2"
  seed_bare_repo "$2" "seed"
  seed_bare_repo "$2" "second"
  init_monorepo "$1"
  add_splice "$1" "$2" "vendor/a"
  commit_local "$1" "vendor/a" "local change"
}

# Prints the rebuild of vendor/a with the synced commit's message replaced
# by <message>: an edit to history the upstream already has.
reworded_synced() {
  local synced rebuilt second
  synced="$(splice_config vendor/a commit)"
  rebuilt="$(rebuild_splice vendor/a)"
  second="$(git commit-tree --no-gpg-sign "$synced^{tree}" -p "$synced^" -m "$1")"
  git commit-tree --no-gpg-sign "$rebuilt^{tree}" -p "$second" -m "local change"
}

@test "push --rebuilt-commit: refuses to edit the synced commit without --force" {
  scenario_push_ahead_after_two "$monorepo" "$upstream"
  cd "$monorepo"
  local edited synced
  edited="$(reworded_synced "second, reworded")"
  synced="$(splice_config vendor/a commit)"
  run cmd_push --rebuilt-commit "$edited" vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a: ${edited:0:7} doesn't contain the synced commit ${synced:0:7} -- edit only the commits after it, or replace published ones with --force" ]
  [ "$(git -C "$upstream" rev-parse main)" = "$synced" ]
}

@test "push --force --rebuilt-commit: edits history before the synced commit, and the next pull records it" {
  scenario_push_ahead_after_two "$monorepo" "$upstream"
  cd "$monorepo"
  local edited
  edited="$(reworded_synced "second, reworded")"
  run cmd_push --force --rebuilt-commit "$edited" vendor/a
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ok   vendor/a: pushed ${edited:0:7} to main" ]
  [ "$(git -C "$upstream" log --format=%s main)" = "$(printf '%s\n' "local change" "second, reworded" "seed")" ]
  run cmd_pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a commit)" = "$edited" ]
  run cmd_push vendor/a
  [ "$output" = "ok   vendor/a: nothing to push" ]
}

@test "push --force --rebuilt-commit: takes a commit without shared history too, as push --force does" {
  scenario_push_ahead_after_two "$monorepo" "$upstream"
  cd "$monorepo"
  local root
  root="$(git commit-tree --no-gpg-sign "$(rebuild_splice vendor/a)^{tree}" -m "squashed")"
  run cmd_push --force --rebuilt-commit "$root" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" rev-parse main)" = "$root" ]
  run cmd_pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a commit)" = "$root" ]
}

# Builds a monorepo at $1 and upstream at $2 for history shape $3, with
# the synced commit U "second" on top of "seed", and prints the commit to
# give --rebuilt-commit.
rebuilt_commit_shape() {
  local monorepo="$1" upstream="$2" shape="$3" synced rebuilt
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  seed_bare_repo "$upstream" "second"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" vendor/a
  cd "$monorepo"
  synced="$(splice_config vendor/a commit)"
  case "$shape" in
    reworded-after-U | reworded-U | rebuild | root)
      commit_local "$monorepo" vendor/a "local change"
      ;;
    without-cancelling-commits)
      commit_local "$monorepo" vendor/a "local change"
      commit_local "$monorepo" vendor/a "temporary" tmp.txt
      git rm -q vendor/a/tmp.txt && git commit -q -m "revert temporary"
      ;;
    U)
      commit_local "$monorepo" vendor/a "temporary" tmp.txt
      git rm -q vendor/a/tmp.txt && git commit -q -m "revert temporary"
      ;;
    older-than-U)
      echo seed >vendor/a/file.txt && git commit -q -am "revert second"
      ;;
  esac
  rebuilt="$(rebuild_splice vendor/a)"
  case "$shape" in
    reworded-after-U) git commit-tree --no-gpg-sign "$rebuilt^{tree}" -p "$rebuilt^" -m "reworded" ;;
    reworded-U) reworded_synced "second, reworded" ;;
    rebuild) echo "$rebuilt" ;;
    root) git commit-tree --no-gpg-sign "$rebuilt^{tree}" -m "squashed" ;;
    without-cancelling-commits) git rev-parse "$rebuilt~2" ;;
    U) echo "$synced" ;;
    older-than-U) git rev-parse "$synced^" ;;
  esac
}

@test "push --rebuilt-commit: accepts exactly the commits the monorepo rebuilds after pull --bump, so the next push sends nothing else" {
  local shape given accepted rebuilds
  for shape in reworded-after-U reworded-U rebuild root without-cancelling-commits U older-than-U; do
    given="$(rebuilt_commit_shape "$BATS_TEST_TMPDIR/$shape/m" "$BATS_TEST_TMPDIR/$shape/u.git" "$shape")"
    cd "$BATS_TEST_TMPDIR/$shape/m"
    run cmd_push --force --rebuilt-commit "$given" vendor/a
    accepted=$([ "$status" -eq 0 ] && echo yes || echo no)

    given="$(rebuilt_commit_shape "$BATS_TEST_TMPDIR/$shape/m2" "$BATS_TEST_TMPDIR/$shape/u2.git" "$shape")"
    cd "$BATS_TEST_TMPDIR/$shape/m2"
    git push -q --force "$BATS_TEST_TMPDIR/$shape/u2.git" "$given:refs/heads/main"
    run cmd_pull --bump vendor/a
    rebuilds=$([ "$(rebuild_splice vendor/a)" = "$given" ] && echo yes || echo no)

    echo "$shape: push accepts: $accepted, rebuilt after pull --bump: $rebuilds"
    [ "$accepted" = "$rebuilds" ]
  done
}

@test "push --rebuilt-commit: refuses while the synced commit isn't here, since the given commit can't contain it" {
  scenario_never_fetched "$monorepo" "$upstream"
  cd "$monorepo"
  local root synced
  content_tree HEAD vendor/a
  root="$(git commit-tree --no-gpg-sign "$CONTENT_TREE" -m "squashed")"
  synced="$(splice_config vendor/a commit)"
  run cmd_push --rebuilt-commit "$root" vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a: synced commit ${synced:0:7} isn't available locally -- run 'git splice fetch vendor/a'" ]
  [ "$(git -C "$upstream" rev-parse main)" = "$synced" ]
}

@test "push --rebuilt-commit: takes a commit and exactly one splice" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_push --rebuilt-commit nope vendor/a
  [ "$output" = "!!   --rebuilt-commit: unknown commit: nope" ]
  run cmd_push --rebuilt-commit HEAD vendor/a vendor/b
  [ "$output" = "!!   --rebuilt-commit takes exactly one splice" ]
  run cmd_push --rebuilt-commit HEAD --all
  [ "$output" = "!!   --rebuilt-commit takes exactly one splice" ]
  run cmd_push vendor/a --rebuilt-commit
  [ "$output" = "!!   --rebuilt-commit needs a commit" ]
  run cmd_status --rebuilt-commit HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   unknown option: --rebuilt-commit" ]]
}
