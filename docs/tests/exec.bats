setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load '../09-scenarios/01-everyday-sync/02-up-to-date/setup'
  load '../09-scenarios/01-everyday-sync/04-never-fetched/setup'
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
