# Wiring of the entrypoint, such as a lib file it forgets to source, or a
# symlinked install that can't find lib/.

setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  entrypoint="$ENTRYPOINT"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "cli: no args prints usage to stderr and exits 1" {
  run "$entrypoint"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: git splice"* ]]
}

@test "cli: -h prints usage and exits 0" {
  run "$entrypoint" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: git splice"* ]]
}

@test "cli: unknown command errors and exits 1" {
  run "$entrypoint" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command: bogus"* ]]
}

@test "cli: each command's -h and --help show the same structured help" {
  local cmd short_help
  for cmd in clone init fetch merge pull push status diff log key boundary rebuild; do
    run "$entrypoint" "$cmd" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *$'NAME\n'"    git-splice-$cmd - "* ]]
    [[ "$output" == *$'\nSYNOPSIS\n'"    git splice $cmd "* ]]
    [[ "$output" == *$'\nDESCRIPTION\n'* ]]
    short_help="$output"

    run "$entrypoint" "$cmd" --help
    [ "$status" -eq 0 ]
    [ "$output" = "$short_help" ]
  done
}

@test "cli: top-level help lists every command" {
  run "$entrypoint" --help
  local cmd
  for cmd in clone init fetch merge pull push status diff log boundary rebuild; do
    [[ "$output" == *"  $cmd "* ]]
  done
}

@test "cli: -- terminates options so a path named like a flag is treated literally" {
  load 'scenarios/01-everyday-sync/02-up-to-date/setup'
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  local cmd
  for cmd in boundary diff fetch log merge pull push rebuild status; do
    run "$entrypoint" "$cmd" -- -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a splice: -h"* ]]
  done
}

@test "cli: splicing in or out needs a path or --all, looking doesn't" {
  load 'scenarios/01-everyday-sync/02-up-to-date/setup'
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  local cmd
  for cmd in merge pull push; do
    run "$entrypoint" "$cmd"
    [ "$status" -eq 1 ]
    [[ "$output" == *"which splice?"* ]]
  done
  for cmd in status diff log fetch; do
    run "$entrypoint" "$cmd"
    [ "$status" -eq 0 ]
  done
}

@test "cli: works through a symlink, as the real install does" {
  local bindir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bindir"
  ln -s "$entrypoint" "$bindir/git-splice"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"

  run "$bindir/git-splice" clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
  run "$bindir/git-splice" status
  [ "${lines[*]:1}" = "  up to date  vendor/a" ]
  commit_local "$monorepo" "vendor/a" "local"
  run "$bindir/git-splice" push vendor/a
  [ "$status" -eq 0 ]
  run "$bindir/git-splice" pull --all
  [ "$status" -eq 0 ]
}

@test "cli: runs from any subfolder" {
  load 'scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/setup'
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo/vendor/a"
  run "$entrypoint" status
  [ "${lines[1]}" = "  ahead 1  vendor/a" ]
}

@test "cli: every command refuses a detached HEAD" {
  load 'scenarios/01-everyday-sync/02-up-to-date/setup'
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q --detach
  local cmd
  for cmd in status diff log fetch "merge --all" "pull --all" "push --all"; do
    # shellcheck disable=SC2086
    run "$entrypoint" $cmd
    [ "$status" -eq 1 ]
    [[ "$output" == *"detached HEAD"* ]]
    [[ "$output" != *"ok "* ]]
  done
}

@test "cli: Cargo.toml and Cargo.lock have the bash entrypoint's version" {
  local root="$BATS_TEST_DIRNAME/.." version
  version="$(sed -n 's/^VERSION=\([^ ]*\).*/\1/p' "$root/git-splice")"
  grep -qx "version = \"$version\"" "$root/Cargo.toml"
  grep -A1 -x 'name = "git-splice"' "$root/Cargo.lock" | grep -qx "version = \"$version\""
}

@test "cli: --version prints VERSION" {
  local version
  version="$(sed -n 's/^VERSION=\([^ ]*\).*/\1/p' "$BATS_TEST_DIRNAME/../git-splice")"
  run "$entrypoint" --version
  [ "$status" -eq 0 ]
  [ "$output" = "git splice version $version" ]
}

@test "cli: VERSION carries the marker release-please bumps it by" {
  grep -qx 'VERSION=[0-9.]* # x-release-please-version' "$BATS_TEST_DIRNAME/../git-splice"
}

@test "cli: refuses a Git older than 2.40" {
  local bindir="$BATS_TEST_TMPDIR/oldgit"
  mkdir -p "$bindir"
  printf '#!/bin/sh\necho "git version 2.39.5"\n' >"$bindir/git"
  chmod +x "$bindir/git"
  PATH="$bindir:$PATH" run "$entrypoint" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires Git >= 2.40"* ]]
}

@test "cli: refuses an argument that isn't valid UTF-8, instead of changing it" {
  [[ "$ENTRYPOINT" == */target/* ]] || skip "bash takes any bytes"
  run "$entrypoint" status $'caf\xe9'
  [ "$status" -eq 1 ]
  [ "$output" = "!!   arguments must be valid UTF-8" ]
}
