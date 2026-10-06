setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/up-to-date/setup'
  load 'scenarios/never-fetched/setup'
  load 'scenarios/up-to-date/shared-remote-url/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "fetch: brings every upstream branch into refs/splices/<key>/" {
  scenario_never_fetched "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "on a branch" feature
  cd "$monorepo"
  run cmd_fetch
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a fetched" ]
  git rev-parse --verify --quiet "$(upstream_refs "$upstream")main"
  git rev-parse --verify --quiet "$(upstream_refs "$upstream")feature"
  [ -z "$(git remote)" ]
}

@test "fetch: says when the branch this one syncs with moved" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  cd "$monorepo"
  run cmd_fetch vendor/a
  [[ "$output" == "ok   vendor/a fetched (main moved "*..*")" ]]
}

@test "fetch: prunes branches deleted upstream" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "on a branch" feature
  cd "$monorepo"
  cmd_fetch
  git -C "$upstream" branch -D feature >/dev/null
  cmd_fetch
  ! git rev-parse --verify --quiet "$(upstream_refs "$upstream")feature"
}

@test "fetch: a failing upstream is reported, the others still fetch" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/b/.splice upstream.origin.url "$BATS_TEST_TMPDIR/nowhere.git"
  git commit -q -am "break vendor/b"
  run cmd_fetch
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok   vendor/a fetched"* ]]
  [[ "$output" == *"Failed: vendor/b"* ]]
}

@test "fetch: honors url.<base>.insteadOf, since it works on URLs" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.origin.url "example:upstream.git"
  git commit -q -am "use a short URL"
  git config "url.$BATS_TEST_TMPDIR/.insteadOf" "example:"
  run cmd_fetch
  [ "$status" -eq 0 ]
}

@test "fetch: fetches an upstream that several splices share once, and reports each" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  cd "$monorepo"
  local fetches="$BATS_TEST_TMPDIR/fetches"
  git() {
    [[ "$1" == fetch && "$*" == *"refs/heads/*:"* ]] && echo x >>"$fetches"
    command git "$@"
  }
  run cmd_fetch
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a fetched (main moved"* ]]
  [[ "$output" == *"ok   vendor/b fetched (main moved"* ]]
  [ "$(wc -l <"$fetches")" -eq 1 ]
}

@test "fetch: a splice without a synced commit yet fetches its upstream once" {
  load 'scenarios/init-new-upstream/setup'
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  splice init lib/a "$upstream" >/dev/null
  git() {
    [[ "$1" == fetch ]] && echo fetch >>"$BATS_TEST_TMPDIR/fetches"
    command git "$@"
  }
  run cmd_fetch lib/a
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$BATS_TEST_TMPDIR/fetches")" -eq 1 ]
}

@test "fetch: shows what git printed on a successful fetch, once per upstream" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  git() {
    [[ "$1" == fetch ]] && echo "warning: from the transport" >&2
    command git "$@"
  }
  run cmd_fetch
  [ "$status" -eq 0 ]
  [ "$(grep -c "warning: from the transport" <<<"$output")" -eq 1 ]
  [[ "$output" == *"ok   vendor/a fetched"* && "$output" == *"ok   vendor/b fetched"* ]]
}
