# Where the rebuilds of earlier runs ended, in .git/splice-rebuilds:
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

@test "rebuild cache: a remembered commit that gc pruned is rebuilt, without an error" {
  three_unpushed
  local rebuilt object
  rebuilt="$(splice rebuild vendor/a)"
  object=".git/objects/${rebuilt:0:2}/${rebuilt:2}"
  [ -f "$object" ]
  rm "$object"
  [ "$(splice rebuild vendor/a 2>"$BATS_TEST_TMPDIR/stderr")" = "$rebuilt" ]
  [ ! -s "$BATS_TEST_TMPDIR/stderr" ]
  [ -f "$object" ]
}

@test "rebuild cache: a file that isn't one is ignored and started over" {
  three_unpushed
  local rebuilt
  rebuilt="$(splice rebuild vendor/a)"
  printf 'something else\n' >.git/splice-rebuilds
  [ "$(splice rebuild vendor/a)" = "$rebuilt" ]
  grep -q '^{"version":3,' .git/splice-rebuilds
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
  [ "$(grep -o '"path":"vendor/a"' .git/splice-rebuilds | wc -l)" -eq 0 ]
}

# Prints the id of a commit like HEAD, with vendor/a/other.txt changed.
head_with_other_contents() {
  local tree
  tree="$(printf 'replaced\n' | git hash-object -w --stdin)"
  tree="$(git ls-tree HEAD:vendor/a | sed "s/[0-9a-f]\{40,\}\tother.txt\$/$tree\tother.txt/" | git mktree)"
  tree="$(git ls-tree HEAD | sed "s/[0-9a-f]\{40,\}\tvendor\$/$(printf '040000 tree %s\ta\n' "$tree" | git mktree)\tvendor/" | git mktree)"
  git commit-tree "$tree" -p HEAD^1 -m three
}

@test "rebuild cache: with replace refs, Git reads other commits under the same ids, so nothing is remembered" {
  three_unpushed
  local before replaced
  before="$(splice rebuild vendor/a)"
  git replace HEAD "$(head_with_other_contents)"
  replaced="$(splice rebuild vendor/a)"
  [ "$replaced" != "$before" ]
  [ "$(git show "$replaced:other.txt")" = replaced ]
  [ "$(commits_written rebuild vendor/a)" -gt 0 ]
}

@test "rebuild cache: with grafts, Git reads other parents under the same ids, so nothing is remembered" {
  three_unpushed
  local before grafted
  before="$(splice rebuild vendor/a)"
  git config advice.graftFileDeprecated false
  echo "$(git rev-parse HEAD) $(git rev-parse HEAD~3)" >.git/info/grafts
  grafted="$(splice rebuild vendor/a)"
  [ "$grafted" != "$before" ]
  [ "$(commits_written rebuild vendor/a)" -gt 0 ]
}

@test "rebuild cache: replace refs under GIT_REPLACE_REF_BASE count too" {
  three_unpushed
  local before replaced
  before="$(splice rebuild vendor/a)"
  export GIT_REPLACE_REF_BASE=refs/elsewhere/
  git replace HEAD "$(head_with_other_contents)"
  replaced="$(splice rebuild vendor/a)"
  [ "$replaced" != "$before" ]
  [ "$(git show "$replaced:other.txt")" = replaced ]
}

@test "rebuild cache: grafts in GIT_GRAFT_FILE count too" {
  three_unpushed
  local before grafted
  before="$(splice rebuild vendor/a)"
  git config advice.graftFileDeprecated false
  export GIT_GRAFT_FILE="$BATS_TEST_TMPDIR/grafts"
  echo "$(git rev-parse HEAD) $(git rev-parse HEAD~3)" >"$GIT_GRAFT_FILE"
  grafted="$(splice rebuild vendor/a)"
  [ "$grafted" != "$before" ]
}

@test "rebuild cache: the walks of a splice inside, one per commit of the splice around it, aren't remembered" {
  scenario_nested_splices "$monorepo" "$upstream"
  local n
  for n in 1 2 3 4; do
    commit_local "$monorepo" vendor/a/b "b change $n" "b$n.txt"
  done
  cd "$monorepo"
  splice rebuild vendor/a >/dev/null
  [ "$(grep -o '"path":"vendor/a/b"' .git/splice-rebuilds | wc -l)" -le 1 ]
}

@test "rebuild cache: in a shallow clone, which hides parents until a deeper fetch, nothing is remembered" {
  three_unpushed
  local rebuilt
  rebuilt="$(splice rebuild vendor/a)"
  git clone -q --depth 6 "file://$monorepo" "$BATS_TEST_TMPDIR/shallow"
  cd "$BATS_TEST_TMPDIR/shallow"
  [ "$(git rev-parse --is-shallow-repository)" = true ]
  git fetch -q "$monorepo" 'refs/splices/*:refs/splices/*'
  [ "$(splice rebuild vendor/a)" = "$rebuilt" ]
  [ ! -e .git/splice-rebuilds ]
}
