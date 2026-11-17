setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load '../09-scenarios/01-everyday-sync/02-up-to-date/setup'
  load '../09-scenarios/01-everyday-sync/04-never-fetched/setup'
  load '../09-scenarios/05-nested-splices/01-nested-splices/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "exec: after-fetch runs once the fetch is reported" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  cd "$monorepo"
  run splice pull --exec 'echo "hook: $GIT_SPLICE_EVENT"' vendor/a
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "ok   vendor/a fetched (main moved "* ]]
  [ "${lines[1]}" = "hook: after-fetch" ]
}

@test "exec: a hook stopping at after-fetch still shows the failed fetch and forgets its new upstream" {
  scenario_never_fetched "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.origin.url "$BATS_TEST_TMPDIR/nowhere.git"
  git commit -q -am "break vendor/a"
  run splice pull --exec 'exit 3' vendor/a
  [ "$status" -eq 3 ]
  [[ "$output" == *"nowhere.git"* ]]
  [ -z "$(git config --get-regexp '^splice\..*\.url$')" ]
}

# Both upstreams move on: a's and, below it, b's.
nested_updates() {
  scenario_nested_splices "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "a change" main other.txt
  seed_bare_repo "${upstream%.git}-b.git" "b change" main other.txt
  cd "$monorepo"
  start="$(git rev-parse HEAD)"
}

@test "exec: a hook stopping a recursive pull says where, and a re-run makes the one commit" {
  for event in after-merge before-fold after-fold; do
    nested_updates
    run splice pull --recursive --exec "test \"\$GIT_SPLICE_EVENT\" != $event" vendor/a
    [ "$status" -eq 1 ]
    [[ "$output" == *"--exec stopped pull at $event"*", what it did so far stays -- re-run pull to go on" ]]
    run splice pull --recursive vendor/a
    [ "$status" -eq 0 ]
    [ "$(git rev-list --count "$start..HEAD")" -eq 1 ]
    [ "$(git show HEAD:vendor/a/other.txt)" = "a change" ]
    [ "$(git show HEAD:vendor/a/b/other.txt)" = "b change" ]
    ! git rev-parse --verify --quiet SPLICE_PULL_START
    cd "$BATS_TEST_TMPDIR" && rm -rf "$BATS_TEST_TMPDIR"/*
  done
}

@test "exec: a hook stopping pull --rebase --recursive on a detached HEAD says so, and a re-run replays the own commit" {
  nested_updates
  commit_local "$monorepo" vendor/a "a local"
  run splice pull --rebase --recursive --exec 'test "$GIT_SPLICE_EVENT" != after-merge' vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"--exec stopped pull at after-merge of vendor/a"* ]]
  [[ "$output" == *"The pulls are on a detached HEAD, 'main' is as it was"* ]]
  run splice pull --rebase --recursive vendor/a
  [ "$status" -eq 0 ]
  [ "$(git symbolic-ref HEAD)" = refs/heads/main ]
  [ "$(git log -1 --format=%s)" = "a local" ]
  [ "$(git show HEAD:vendor/a/b/other.txt)" = "b change" ]
}

@test "exec: a hook stopping push --all after the first push, and a re-run pushes the rest" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b "b local"
  commit_local "$monorepo" vendor/a "a local"
  cd "$monorepo"
  run splice push --all --exec 'test "$GIT_SPLICE_EVENT" != after-push'
  [ "$status" -eq 1 ]
  [[ "$output" == *"--exec stopped push at after-push of vendor/a/b, what it did so far stays -- re-run push to go on" ]]
  [ "$(git -C "$upstream" log -1 --format=%s main)" != "a local" ]
  run splice push --all
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "a local" ]
}

@test "exec: refuses a second --exec, which would replace the first" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice push --exec true --exec false vendor/a
  [ "$status" -ne 0 ]
  [[ "$output" == *"--exec can be given once; it runs one shell command"* ]]
}

@test "exec: a pull hook that changes HEAD, the configuration, a tracked file or the index stops the pull" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  local change
  for change in \
    'git commit -q --allow-empty -m hook' \
    'git config hook.changed true' \
    'echo changed >>vendor/a/file.txt' \
    'echo new >new.txt && git add new.txt'; do
    seed_bare_repo "$upstream" "change for $change"
    run splice pull --exec "test \"\$GIT_SPLICE_EVENT\" != after-fetch || { $change; }" vendor/a
    [ "$status" -eq 1 ]
    [[ "$output" == *"repository state changed at a pull checkpoint -- start a new pull" ]]
    git reset -q --hard
    git clean -qfd
    git config --unset hook.changed || true
  done
}

@test "exec: a push hook that changes the configuration stops the push before publishing" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  commit_local "$monorepo" vendor/a "local change"
  before="$(git --git-dir="$upstream" rev-parse main)"
  run splice push --exec 'test "$GIT_SPLICE_EVENT" != after-rebuild || git config hook.changed true' vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"repository state changed at a push checkpoint -- start a new push" ]]
  [ "$(git --git-dir="$upstream" rev-parse main)" = "$before" ]
}
