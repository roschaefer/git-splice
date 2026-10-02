# Unlike the other *.bats files, these run the real entrypoint as a
# subprocess (never sourced functions) -- the only layer that would catch
# wiring bugs such as a lib file the entrypoint forgets to source, or a
# symlinked install that can't find lib/.

setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  entrypoint="$BATS_TEST_DIRNAME/../git-splice"
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

@test "cli: each command's own -h works" {
  local cmd
  for cmd in clone init fetch merge pull push status diff log; do
    run "$entrypoint" "$cmd" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: git splice $cmd"* ]]
  done
}

@test "cli: top-level help lists every command" {
  run "$entrypoint" --help
  local cmd
  for cmd in clone init fetch merge pull push status diff log; do
    [[ "$output" == *"  $cmd "* ]]
  done
}

@test "cli: -- terminates options so a path named like a flag is treated literally" {
  load 'scenarios/up-to-date/setup'
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  local cmd
  for cmd in diff fetch log merge pull push status; do
    run "$entrypoint" "$cmd" -- -h
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a splice: -h"* ]]
  done
}

@test "cli: splicing in or out needs a path or --all, looking doesn't" {
  load 'scenarios/up-to-date/setup'
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
  [ "$output" = "ok   vendor/a -> main (up to date)" ]
  commit_local "$monorepo" "vendor/a" "local"
  run "$bindir/git-splice" push vendor/a
  [ "$status" -eq 0 ]
  run "$bindir/git-splice" pull --all
  [ "$status" -eq 0 ]
}

@test "cli: runs from any subfolder" {
  load 'scenarios/push-ahead/setup'
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo/vendor/a"
  run "$entrypoint" status
  [ "${lines[0]}" = "ok   vendor/a -> main (push)" ]
}

@test "cli: every command treats a .splice inside a splice as content" {
  load 'scenarios/nested-splices/setup'
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  local cmd
  for cmd in status diff log fetch "merge --all" "pull --all" "push --all"; do
    # shellcheck disable=SC2086
    run "$entrypoint" $cmd
    [ "$status" -eq 0 ]
    [[ "$output" != *"vendor/pkg/extra"* ]]
  done
}

@test "cli: refuses a detached HEAD" {
  load 'scenarios/up-to-date/setup'
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git checkout -q --detach
  run "$entrypoint" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"detached HEAD"* ]]
}

@test "cli: --version prints VERSION" {
  local version
  version="$(sed -n 's/^VERSION=\([^ ]*\).*/\1/p' "$entrypoint")"
  run "$entrypoint" --version
  [ "$status" -eq 0 ]
  [ "$output" = "git splice version $version" ]
}

@test "cli: VERSION carries the marker release-please bumps it by" {
  grep -qx 'VERSION=[0-9.]* # x-release-please-version' "$entrypoint"
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
