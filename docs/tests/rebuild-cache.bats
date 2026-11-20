# The rebuilt commits remembered between runs, in .git/splice-rebuilds:
# they save time and change no answer.

setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load '../09-scenarios/01-everyday-sync/02-up-to-date/setup'
  load '../09-scenarios/05-nested-splices/01-nested-splices/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

# A splice with three unpushed commits.
three_unpushed() {
  scenario_up_to_date "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "one"
  commit_local "$monorepo" . "outside" outside.txt
  commit_local "$monorepo" vendor/a "two"
  commit_local "$monorepo" vendor/a "three" other.txt
  cd "$monorepo"
}

# Runs git-splice with arguments $@, and prints how many commits it wrote
# with git commit-tree.
commits_written() {
  local trace="$BATS_TEST_TMPDIR/trace"
  rm -f "$trace"
  GIT_TRACE="$trace" splice "$@" >/dev/null 2>&1
  grep -c 'built-in: git commit-tree' "$trace" || true
}

@test "rebuild cache: a second run writes no commit and gives the same rebuild and status" {
  three_unpushed
  local first status
  first="$(splice rebuild vendor/a)"
  status="$(splice status)"
  [ -s .git/splice-rebuilds ]
  [ "$(commits_written rebuild vendor/a)" -eq 0 ]
  [ "$(splice rebuild vendor/a)" = "$first" ]
  [ "$(splice status)" = "$status" ]
  rm .git/splice-rebuilds
  [ "$(splice rebuild vendor/a)" = "$first" ]
}

@test "rebuild cache: a new commit is the only one rebuilt" {
  three_unpushed
  splice rebuild vendor/a >/dev/null
  commit_local "$monorepo" vendor/a "four"
  [ "$(commits_written rebuild vendor/a)" -eq 1 ]
  local cached
  cached="$(splice rebuild vendor/a)"
  rm .git/splice-rebuilds
  [ "$(splice rebuild vendor/a)" = "$cached" ]
}

@test "rebuild cache: a remembered commit that gc pruned is rebuilt" {
  three_unpushed
  local rebuilt object
  rebuilt="$(splice rebuild vendor/a)"
  object=".git/objects/${rebuilt:0:2}/${rebuilt:2}"
  [ -f "$object" ]
  rm "$object"
  [ "$(splice rebuild vendor/a)" = "$rebuilt" ]
  [ -f "$object" ]
}

@test "rebuild cache: a file cut off by an unfinished write is ignored from the cut" {
  three_unpushed
  local rebuilt
  rebuilt="$(splice rebuild vendor/a)"
  truncate -s -10 .git/splice-rebuilds
  [ "$(splice rebuild vendor/a)" = "$rebuilt" ]
  [ "$(commits_written rebuild vendor/a)" -eq 0 ]
}

@test "rebuild cache: a file that isn't one is ignored and started over" {
  three_unpushed
  local rebuilt
  rebuilt="$(splice rebuild vendor/a)"
  printf 'something else\n' >.git/splice-rebuilds
  [ "$(splice rebuild vendor/a)" = "$rebuilt" ]
  [ "$(head -n 1 .git/splice-rebuilds)" = "git-splice rebuilds 1" ]
  [ "$(commits_written rebuild vendor/a)" -eq 0 ]
}

@test "rebuild cache: worktrees share it" {
  three_unpushed
  splice rebuild vendor/a >/dev/null
  git worktree add -q ../worktree
  cd ../worktree
  [ "$(commits_written rebuild vendor/a)" -eq 0 ]
}

@test "rebuild cache: a splice with a splice inside isn't remembered" {
  scenario_nested_splices "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "a change"
  commit_local "$monorepo" vendor/a/b "b change"
  cd "$monorepo"
  local rebuilt
  rebuilt="$(splice rebuild vendor/a)"
  [ "$(commits_written rebuild vendor/a)" -gt 0 ]
  [ "$(splice rebuild vendor/a)" = "$rebuilt" ]
  run grep -c -x vendor/a < <(tr '\0' '\n' <.git/splice-rebuilds)
  [ "$output" = 0 ]
}
