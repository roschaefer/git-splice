setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load '../09-scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/setup'
  load '../09-scenarios/05-nested-splices/01-nested-splices/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  payload="$BATS_TEST_TMPDIR/push.json"
}

pause_push() {
  local result=0
  splice push "$@" >"$payload.next" || result=$?
  if [[ -s "$payload.next" ]]; then mv "$payload.next" "$payload"; fi
  return "$result"
}

continue_push() {
  pause_push --continue-from "$payload" --exec 'cat; exit 1'
}

@test "push checkpoints: pause before and after each upload and never repeat a completed push" {
  scenario_push_ahead "$monorepo" "$upstream"
  local second="$BATS_TEST_TMPDIR/second.git"
  make_bare_repo "$second"
  seed_bare_repo "$second" 'b seed'
  cd "$monorepo"
  splice clone "$second" vendor/b
  commit_local "$monorepo" vendor/b 'b local'
  local head old first
  head="$(git rev-parse HEAD)"
  old="$(git -C "$upstream" rev-parse main)"
  run pause_push --all --exec 'cat; exit 1'
  [ "$status" -eq 1 ]
  jq -e '.operation == "push" and .event.checkpoint == "after-rebuild" and .event.path == "vendor/a" and .result.rebuilt_commit == null' "$payload"
  [ "$(git -C "$upstream" rev-parse main)" = "$old" ]
  first="$(jq -r .event.rebuilt_commit "$payload")"
  run continue_push
  [ "$status" -eq 1 ]
  jq -e '.event.checkpoint == "after-push" and .event.path == "vendor/a"' "$payload"
  [ "$(git -C "$upstream" rev-parse main)" = "$first" ]
  mv "$upstream" "$upstream.offline"
  run continue_push
  [ "$status" -eq 1 ]
  jq -e '.event.checkpoint == "after-rebuild" and .event.path == "vendor/b"' "$payload"
  run continue_push
  [ "$status" -eq 1 ]
  jq -e '.event.checkpoint == "after-push" and .event.path == "vendor/b"' "$payload"
  [ "$(git -C "$second" log -1 --format=%s main)" = 'b local' ]
  run continue_push
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD)" = "$head" ]
  [ -z "$(git status --porcelain)" ]
}

@test "push checkpoints: script returns an edited rebuild for continuation with rebuilt-commit validation" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local head old
  head="$(git rev-parse HEAD)"
  old="$(git -C "$upstream" rev-parse main)"
  export PUSH_SCRIPT="$BATS_TEST_DIRNAME/../09-scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/reword-push.sh"
  run pause_push --exec 'bash "$PUSH_SCRIPT"' vendor/a
  [ "$status" -eq 1 ]
  [ "$(git -C "$upstream" rev-parse main)" = "$old" ]
  local edited
  edited="$(jq -r .result.rebuilt_commit "$payload")"
  run splice push --continue-from "$payload" --exec 'bash "$PUSH_SCRIPT"'
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" rev-parse main)" = "$edited" ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = 'reviewed history' ]
  [[ "$output" == *'pull --bump'* ]]
  [ "$(git rev-parse HEAD)" = "$head" ]
}

@test "push checkpoints: edited rebuilds with different files or unrelated history are refused before upload" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run pause_push --exec 'cat; exit 1' vendor/a
  [ "$status" -eq 1 ]
  cp "$payload" "$payload.original"
  local old rebuilt empty wrong unrelated
  old="$(git -C "$upstream" rev-parse main)"
  rebuilt="$(jq -r .event.rebuilt_commit "$payload")"
  empty="$(git mktree </dev/null)"
  wrong="$(printf 'wrong files\n' | git commit-tree "$empty" -p "$old")"
  jq --arg commit "$wrong" '.result.rebuilt_commit = $commit' "$payload.original" >"$payload"
  run splice push --continue-from "$payload" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'has other files than the folder'* ]]
  [ "$(git -C "$upstream" rev-parse main)" = "$old" ]
  unrelated="$(printf 'unrelated history\n' | git commit-tree "$(git rev-parse "$rebuilt^{tree}")")"
  jq --arg commit "$unrelated" '.result.rebuilt_commit = $commit' "$payload.original" >"$payload"
  run splice push --continue-from "$payload" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *"doesn't contain the synced commit"* ]]
  [ "$(git -C "$upstream" rev-parse main)" = "$old" ]
}

@test "push checkpoints: force permits a replacement history with matching files" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run pause_push --force --exec 'cat; exit 1' vendor/a
  [ "$status" -eq 1 ]
  local rebuilt replacement
  rebuilt="$(jq -r .event.rebuilt_commit "$payload")"
  replacement="$(printf 'replacement history\n' | git commit-tree "$(git rev-parse "$rebuilt^{tree}")")"
  jq --arg commit "$replacement" '.result.rebuilt_commit = $commit' "$payload" >"$payload.next"
  mv "$payload.next" "$payload"
  run splice push --continue-from "$payload" --exec true
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" rev-parse main)" = "$replacement" ]
}

@test "push checkpoints: a no-op does not run scripts and a successful script preserves ordinary push" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run splice push --exec true vendor/a
  [ "$status" -eq 0 ]
  run splice push --exec 'exit 99' vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *'nothing to push'* ]]
}

@test "push checkpoints: remote advancement rejects the pinned push without silently rebuilding or forcing" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run pause_push --exec 'cat; exit 1' vendor/a
  [ "$status" -eq 1 ]
  seed_bare_repo "$upstream" 'remote work'
  local remote
  remote="$(git -C "$upstream" rev-parse main)"
  run splice push --continue-from "$payload" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'push failed'* ]]
  [ "$(git -C "$upstream" rev-parse main)" = "$remote" ]
}

@test "push checkpoints: changed HEAD and results at the wrong checkpoint are refused" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run pause_push --exec 'cat; exit 1' vendor/a
  [ "$status" -eq 1 ]
  run continue_push
  [ "$status" -eq 1 ]
  jq '.result.rebuilt_commit = .event.rebuilt_commit' "$payload" >"$payload.next"
  run splice push --continue-from "$payload.next" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'requires a push after-rebuild checkpoint'* ]]
  git commit --allow-empty -qm 'intervening commit'
  run splice push --continue-from "$payload" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'HEAD changed since the push checkpoint'* ]]
}

@test "push checkpoints: a failed nested upload blocks its ancestor but independent splices still push" {
  scenario_nested_splices "$monorepo" "$upstream"
  local child="$BATS_TEST_TMPDIR/upstream-b.git" independent="$BATS_TEST_TMPDIR/independent.git"
  make_bare_repo "$independent"
  seed_bare_repo "$independent" 'independent seed'
  cd "$monorepo"
  splice clone "$independent" vendor/x
  commit_local "$monorepo" vendor/a/b 'b local'
  commit_local "$monorepo" vendor/a 'a local'
  commit_local "$monorepo" vendor/x 'x local'
  printf '#!/bin/sh\nexit 1\n' >"$child/hooks/pre-receive"
  chmod +x "$child/hooks/pre-receive"
  local old
  old="$(git -C "$upstream" rev-parse main)"
  run splice push --all --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'vendor/a: not pushed, since vendor/a/b below it failed'* ]]
  [ "$(git -C "$upstream" rev-parse main)" = "$old" ]
  [ "$(git -C "$independent" log -1 --format=%s main)" = 'x local' ]
}

@test "push checkpoints: tracking is complete at after-push and continuation does not repeat it" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run pause_push --branch review --track --exec 'cat; exit 1' vendor/a
  [ "$status" -eq 1 ]
  ! git config --get-all branch.main.splice
  run continue_push
  [ "$status" -eq 1 ]
  [ "$(jq -r .event.checkpoint "$payload")" = after-push ]
  [ "$(git config --get-all branch.main.splice)" = "$(splice key vendor/a):review" ]
  run splice push --continue-from "$payload" --exec 'exit 99'
  [ "$status" -eq 0 ]
}

@test "push checkpoints: rebuilt-commit refs are resolved before the pause" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt
  rebuilt="$(splice rebuild vendor/a)"
  git update-ref refs/heads/prepared "$rebuilt"
  run pause_push --rebuilt-commit prepared --exec 'cat; exit 1' vendor/a
  [ "$status" -eq 1 ]
  git update-ref refs/heads/prepared HEAD
  run splice push --continue-from "$payload" --exec true
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" rev-parse main)" = "$rebuilt" ]
}

@test "push checkpoints: replacement results keep the one-named-splice rebuilt-commit rule" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local old
  old="$(git -C "$upstream" rev-parse main)"
  run pause_push --all --exec 'cat; exit 1'
  [ "$status" -eq 1 ]
  jq '.result.rebuilt_commit = .event.rebuilt_commit' "$payload" >"$payload.next"
  run splice push --continue-from "$payload.next" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'takes exactly one explicitly named splice'* ]]
  [ "$(git -C "$upstream" rev-parse main)" = "$old" ]
}
