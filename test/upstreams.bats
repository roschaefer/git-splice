setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/several-upstreams/setup'
  load 'scenarios/nested-splices/outer-fork/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  fork="$BATS_TEST_TMPDIR/upstream-fork.git"
}

# Names upstream $2 at URL $3 in $1/.splice, makes $4 (if given) the
# default, and commits it.
add_upstream() {
  git config --file "$1/.splice" "upstream.$2.url" "$3"
  [[ -z "${4:-}" ]] || git config --file "$1/.splice" splice.default-upstream "$4"
  git commit -q -m "$1: add $2" -- "$1/.splice"
}

@test "upstreams: commands use default-upstream of a splice that names several" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "$fork" fork
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ok   vendor/a fetched from fork" ]
  [ "$(git log -1 --format=%s)" = "splice: pull vendor/a from fork/main at $(git -C "$fork" rev-parse --short main)" ]
  [ "$(splice_config vendor/a commit)" = "$(git -C "$fork" rev-parse main)" ]
}

@test "upstreams: a splice with one upstream needs no default-upstream, and messages don't name it" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  run splice status
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a -> main (up to date)" ]
  run splice fetch
  [ "$output" = "ok   vendor/a fetched" ]
}

@test "upstreams: without default-upstream, commands that need one upstream refuse, saying how to choose" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "$fork"
  for command in status diff log "pull vendor/a" "merge vendor/a" "push vendor/a" "key vendor/a"; do
    # shellcheck disable=SC2086 # the command and its arguments
    run splice $command
    [ "$status" -eq 1 ]
    [ "$output" = "!!   vendor/a names upstreams 'origin' and 'fork', but no default -- pass --upstream <name>, or commit one: git config --file vendor/a/.splice splice.default-upstream <name>" ]
  done
  [ -z "$(git for-each-ref refs/splices/company-lib refs/splices/upstream-fork)" ]
}

@test "upstreams: a default-upstream that names none of them is refused" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "$fork" mirror
  run splice status
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a/.splice: default-upstream 'mirror' isn't one of its upstreams ('origin' and 'fork') -- fix it: git config --file vendor/a/.splice splice.default-upstream <name>" ]
}

@test "upstreams: a name given twice, or with other characters than letters, digits, '.', '_' and '-', is refused" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice --add upstream.origin.url "$fork"
  git commit -q -am "origin twice"
  run splice status
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a/.splice names upstream 'origin' twice -- keep one" ]
  git config --file vendor/a/.splice --unset-all upstream.origin.url
  git config --file vendor/a/.splice "upstream.my fork.url" "$fork"
  git commit -q -am "a name with a space"
  run splice status
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a/.splice: 'my fork' isn't supported as an upstream's name -- use letters, digits, '.', '_' and '-'" ]
}

@test "fetch: fetches every upstream of a splice, or only the one --upstream names" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "$fork" fork
  run splice fetch --upstream origin
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a fetched from origin" ]
  [ -z "$(git config --local splice.upstream-fork.url || true)" ]
  run splice fetch
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ok   vendor/a fetched from origin" ]
  [ "${lines[1]}" = "ok   vendor/a fetched from fork" ]
  [ "$(git rev-parse refs/splices/upstream-fork/main)" = "$(git -C "$fork" rev-parse main)" ]
}

@test "fetch: a failing upstream of a splice fails the fetch, and the other one is still fetched" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a gone "$BATS_TEST_TMPDIR/gone.git" origin
  seed_bare_repo "$upstream" "moved"
  run splice fetch
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok   vendor/a fetched from origin (main moved "* ]]
  [[ "$output" == *"!!   vendor/a fetch from gone failed"* ]]
  [[ "$output" == *"!!   Failed: vendor/a" ]]
}

@test "--upstream: a selected splice without that upstream stops the command before anything happens" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "$fork" fork
  splice clone "$upstream" vendor/b >/dev/null
  local head
  head="$(git rev-parse HEAD)"
  run splice pull --upstream fork --all
  [ "$status" -eq 1 ]
  [ "$output" = "!!   no upstream 'fork' in vendor/b -- name only the splices that have one: vendor/a" ]
  [ "$(git rev-parse HEAD)" = "$head" ]
  [ -z "$(git for-each-ref refs/splices/upstream-fork)" ]
  run splice push --upstream fork vendor/b vendor/a
  [ "$output" = "!!   no upstream 'fork' in vendor/b -- name only the splices that have one: vendor/a" ]
  run splice status --upstream mirror
  [ "$output" = "!!   none of these splices has an upstream 'mirror': vendor/a vendor/b" ]
  run splice status --upstream mirror vendor/b
  [ "$output" = "!!   vendor/b has no upstream 'mirror' -- its upstream is 'origin'" ]
}

@test "push --upstream: pushes to the named upstream, and records what it has now" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "$fork" origin
  splice fetch >/dev/null
  splice pull --upstream fork vendor/a >/dev/null
  run splice push vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: pushed $(git -C "$upstream" rev-parse --short main) to origin/main" ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "fork patch" ]
  [ "$(git rev-parse refs/splices/upstream/main)" = "$(git -C "$upstream" rev-parse main)" ]
}

@test "--upstream: hints name it when the upstream in use isn't the default" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "$fork" origin
  splice fetch >/dev/null
  echo "local" >>vendor/a/file.txt
  git commit -q -am "local"
  run splice push --upstream fork vendor/a
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   vendor/a: upstream has commits this branch lacks -- run 'git splice pull --upstream fork vendor/a' first" ]
  run splice status
  [ "$output" = "ok   vendor/a -> origin/main (push: ahead 1)" ]
}

@test "pull --upstream: the splices below are fetched from every upstream they name" {
  scenario_outer_fork "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "${upstream%.git}-fork.git" origin
  add_upstream vendor/a/b fork "$BATS_TEST_TMPDIR/upstream-b-fork.git" origin
  run splice pull --upstream fork vendor/a
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ok   vendor/a fetched from fork" ]
  [ "${lines[1]}" = "ok   vendor/a/b fetched from origin" ]
  [ "${lines[2]}" = "ok   vendor/a/b fetched from fork" ]
}

@test "pull --upstream: a selected splice below uses its own upstream of that name" {
  scenario_outer_fork "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "${upstream%.git}-fork.git" origin
  add_upstream vendor/a/b fork "$BATS_TEST_TMPDIR/upstream-b-fork.git" origin
  run splice pull --upstream fork --all
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a/b commit)" = "$(git -C "$BATS_TEST_TMPDIR/upstream-b-fork.git" rev-parse main)" ]
}
