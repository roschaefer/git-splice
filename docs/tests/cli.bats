# The entrypoint itself: usage, version, and a symlinked install.

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

@test "cli: each command's --help prints its full reference" {
  local cmd
  for cmd in clone init fetch merge pull push status diff log key boundary rebuild; do
    run "$entrypoint" "$cmd" --help
    [ "$status" -eq 0 ]
    [[ "$output" == $'NAME\n'"    git-splice-$cmd - "* ]]
    [[ "$output" == *$'\nSYNOPSIS\n'"    git splice $cmd "* ]]
    [[ "$output" == *$'\nDESCRIPTION\n'* ]]
    [[ "$output" == *"See also: https://git-splice.roschaefer.de/docs/command-reference/"* ]]
  done
}

@test "cli: each command's -h prints its synopsis as usage lines and every option of its --help, without the reference" {
  local cmd full option
  for cmd in clone init fetch merge pull push status diff log key boundary rebuild; do
    full="$("$entrypoint" "$cmd" --help)"
    run "$entrypoint" "$cmd" -h
    [ "$status" -eq 0 ]
    [[ "$output" == "usage: git splice $cmd "* ]]
    [[ "$output" == *$'\n'"'git splice $cmd --help' prints the full reference." ]]
    [[ "$output" != *"DESCRIPTION"* ]]
    [[ "$output" != *"See also:"* ]]
    while IFS= read -r option; do
      [[ "$output" == *$'\n'"$option"$'\n'* ]]
    done < <(sed -n '/^OPTIONS$/,/^[A-Z]/{/^    [^ ]/p}' <<<"$full" | grep -v '^    See also: ')
    [ "${#output}" -lt "${#full}" ]
  done
}

@test "cli: -h cuts each option's description after its first sentence" {
  run "$entrypoint" push -h
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\n    --force\n        Overwrites the upstream branch with the monorepo\'s side: when the\n        two share no history, or to discard commits only upstream has.\n    --rebuilt-commit <commit>\n'* ]]
}

@test "cli: a second synopsis line continues the usage as an 'or:' line" {
  run "$entrypoint" push -h
  [[ "${lines[1]}" == "   or: git splice push "*" --rebuilt-commit <commit> <path>" ]]
}

@test "cli: -h and --help work after a command's other arguments" {
  run "$entrypoint" push vendor/a -h
  [ "$status" -eq 0 ]
  [[ "$output" == "usage: git splice push "* ]]
  run "$entrypoint" push vendor/a --help
  [ "$status" -eq 0 ]
  [[ "$output" == $'NAME\n'* ]]
}

@test "cli: top-level -h and --help print the same command list, as 'git -h' and 'git --help' do" {
  run "$entrypoint" --help
  [ "$status" -eq 0 ]
  local full="$output"
  run "$entrypoint" -h
  [ "$status" -eq 0 ]
  [ "$output" = "$full" ]
  [[ "$output" == *"'git splice <command> -h' for a command's options"* ]]
}

@test "cli: top-level help lists every command" {
  run "$entrypoint" --help
  local cmd
  for cmd in clone init fetch merge pull push status diff log boundary rebuild; do
    [[ "$output" == *"  $cmd "* ]]
  done
}

@test "cli: -- terminates options so a path named like a flag is treated literally" {
  load '../09-scenarios/01-everyday-sync/02-up-to-date/setup'
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
  load '../09-scenarios/01-everyday-sync/02-up-to-date/setup'
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
  load '../09-scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/setup'
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo/vendor/a"
  run "$entrypoint" status
  [ "${lines[1]}" = "  ahead 1  vendor/a" ]
}

@test "cli: every command refuses a detached HEAD" {
  load '../09-scenarios/01-everyday-sync/02-up-to-date/setup'
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

@test "cli: --version prints the version in Cargo.toml and Cargo.lock" {
  local version
  version="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$BATS_TEST_DIRNAME/../../Cargo.toml")"
  grep -A1 -x 'name = "git-splice"' "$BATS_TEST_DIRNAME/../../Cargo.lock" | grep -qx "version = \"$version\""
  run "$entrypoint" --version
  [ "$status" -eq 0 ]
  [ "$output" = "git splice version $version" ]
}

@test "cli: says so when there's no Git" {
  local entrypoint_copy="$BATS_TEST_TMPDIR/no-git/git-splice"
  mkdir -p "$(dirname "$entrypoint_copy")"
  cp "$entrypoint" "$entrypoint_copy"
  PATH="$(dirname "$entrypoint_copy")" run "$entrypoint_copy" status
  [ "$status" -eq 1 ]
  [ "$output" = "!!   git-splice needs Git, and \`git --version\` didn't work" ]
}

@test "cli: says so when Git fails" {
  local bindir="$BATS_TEST_TMPDIR/broken-git"
  mkdir -p "$bindir"
  printf '#!/bin/sh\nexit 1\n' >"$bindir/git"
  chmod +x "$bindir/git"
  PATH="$bindir:$PATH" run "$entrypoint" status
  [ "$status" -eq 1 ]
  [ "$output" = "!!   git-splice needs Git, and \`git --version\` didn't work" ]
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
  run "$entrypoint" status $'caf\xe9'
  [ "$status" -eq 1 ]
  [ "$output" = "!!   arguments must be valid UTF-8" ]
}
