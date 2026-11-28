setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load '../09-scenarios/01-everyday-sync/02-up-to-date/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  cp -r vendor/a vendor/a-copy
  git add vendor/a-copy
  git commit -q -m "copy vendor/a"
}

# Prints the line `git splice status` shows for splice $1.
status_line() {
  splice status | grep -E "  $1( |$)"
}

@test "status: says nothing of mirrors with the same files and .splice" {
  run splice status
  [ "$status" -eq 0 ]
  [[ "$output" != *mirror* ]]
}

@test "status: names the mirror whose files differ, on each mirror's line" {
  commit_local "$monorepo" vendor/a "local change"
  run status_line vendor/a
  [[ "$output" =~ "vendor/a "+"files differ from mirror vendor/a-copy"$ ]]
  run status_line vendor/a-copy
  [[ "$output" =~ "vendor/a-copy "+"files differ from mirror vendor/a"$ ]]
}

@test "status: lists a mirror whose files differ with the splices that need something" {
  commit_local "$monorepo" vendor/a-copy "copy change"
  local output
  output="$(splice status)"
  [[ "$(sed -n '3,$p' <<<"$output")" != *$'\n\n'* ]]
  [[ "$output" == *"up to date"*"vendor/a "*"files differ from mirror vendor/a-copy"* ]]
}

@test "status: names the mirror whose .splice differs, with the same files" {
  commit_local "$monorepo" vendor/a "local change"
  splice push vendor/a
  splice pull vendor/a-copy
  git diff --quiet HEAD:vendor/a HEAD:vendor/a-copy -- ':!.splice'
  run status_line vendor/a
  [[ "$output" =~ "vendor/a "+".splice differs from mirror vendor/a-copy"$ ]]
}

@test "status: says nothing of mirrors once the push is recorded with pull --bump" {
  commit_local "$monorepo" vendor/a "local change"
  splice push vendor/a
  splice pull vendor/a-copy
  splice pull --bump vendor/a
  run splice status
  [ "$status" -eq 0 ]
  [[ "$output" != *mirror* ]]
}

@test "status: names every mirror that differs" {
  cp -r vendor/a vendor/a-third
  git add vendor/a-third
  git commit -q -m "another copy"
  commit_local "$monorepo" vendor/a "local change"
  run status_line vendor/a
  [[ "$output" == *"files differ from mirrors vendor/a-copy, vendor/a-third" ]]
}

@test "status: a splice cloned from the same upstream, with its own id, is no mirror" {
  add_splice "$monorepo" "$upstream" third_party/a
  commit_local "$monorepo" vendor/a "local change"
  run status_line third_party/a
  [[ "$output" != *mirror* ]]
  run status_line vendor/a
  [[ "$output" == *"files differ from mirror vendor/a-copy" ]]
}

@test "push: warns that the mirror's files differ, and still pushes" {
  commit_local "$monorepo" vendor/a "local change"
  local rebuilt
  rebuilt="$(splice rebuild vendor/a)"
  run splice push vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"??   vendor/a: files differ from mirror vendor/a-copy"* ]]
  [[ "$output" == *"vendor/a: pushed ${rebuilt:0:7} to main"* ]]
  [ "$(git -C "$upstream" rev-parse main)" = "$rebuilt" ]
}

@test "push: says nothing of mirrors with the same files and .splice" {
  run splice push vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" != *mirror* ]]
}

@test "pull: says nothing of mirrors that differ" {
  commit_local "$monorepo" vendor/a "local change"
  seed_bare_repo "$upstream" "upstream change" main other.txt
  run splice pull vendor/a-copy
  [ "$status" -eq 0 ]
  [[ "$output" != *mirror* ]]
}
