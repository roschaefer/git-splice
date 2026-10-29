setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/04-upstreams/02-several-upstreams/setup'
  load 'scenarios/05-nested-splices/01-nested-splices/01-outer-fork/setup'
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

@test "upstreams: pulling from one upstream keeps the patch the other still has, though the first never had it" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "$fork" fork
  splice pull vendor/a >/dev/null
  seed_bare_repo "$upstream" "original release" main release.txt
  run splice pull --upstream origin vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/file.txt)" = "$(printf 'seed\nfork patch')" ]
  [ "$(cat vendor/a/release.txt)" = "original release" ]
}

@test "upstreams: pulling after the upstream with the patch is dropped from .splice keeps the patch: the remaining upstream's branch never had it, so it rewrote nothing" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "$fork" fork
  splice pull vendor/a >/dev/null
  seed_bare_repo "$upstream" "original release" main release.txt
  git config --file vendor/a/.splice --remove-section upstream.fork
  git config --file vendor/a/.splice --unset splice.default-upstream
  git commit -q -m "vendor/a: drop fork" -- vendor/a/.splice
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/file.txt)" = "$(printf 'seed\nfork patch')" ]
  [ "$(cat vendor/a/release.txt)" = "original release" ]
}

@test "upstreams: pulling after the upstream with the patch got another URL keeps the patch: the branch it now pulls never had it, so it rewrote nothing" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "$fork" fork
  splice pull vendor/a >/dev/null
  seed_bare_repo "$upstream" "original release" main release.txt
  git config --file vendor/a/.splice --remove-section upstream.origin
  git config --file vendor/a/.splice upstream.fork.url "$upstream"
  git commit -q -m "vendor/a: fork is the original now" -- vendor/a/.splice
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/file.txt)" = "$(printf 'seed\nfork patch')" ]
  [ "$(cat vendor/a/release.txt)" = "original release" ]
}

@test "upstreams: a splice with one upstream needs no default-upstream, and messages don't name it" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  run splice status
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'On branch main\n\n  up to date  vendor/a')" ]
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

@test "upstreams: each upstream has its own default branch, which the monorepo's default branch maps to" {
  scenario_several_upstreams "$monorepo" "$upstream"
  git -C "$fork" branch -m main trunk
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.fork.url "$fork"
  git config --file vendor/a/.splice upstream.fork.default-branch trunk
  git config --file vendor/a/.splice splice.default-upstream origin
  git commit -q -m "vendor/a: add fork, on trunk" -- vendor/a/.splice
  run splice pull --upstream fork vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "splice: pull vendor/a from fork/trunk at $(git -C "$fork" rev-parse --short trunk)" ]
  run splice fetch --upstream origin vendor/a
  run splice status vendor/a
  [ "$output" = "$(printf 'On branch main\n\n  ahead 1  vendor/a -> origin/main')" ]
}

@test "upstreams: a default-branch in [splice], from an earlier version, is refused" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice splice.default-branch master
  git commit -q -m "the earlier format" -- vendor/a/.splice
  run splice status
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/.splice has default-branch in [splice], from an earlier version -- it belongs to an upstream now: upstream.<name>.default-branch"* ]]
}

@test "merge --bump: the bump names the upstream branch it records, like a pull" {
  scenario_several_upstreams "$monorepo" "$upstream"
  local mirror="$BATS_TEST_TMPDIR/mirror.git" target
  git clone -q --bare "$upstream" "$mirror"
  cd "$monorepo"
  add_upstream vendor/a mirror "$mirror" origin
  echo "local" >>vendor/a/file.txt
  git commit -q -am "a local change"
  splice push --upstream mirror vendor/a
  target="$(git -C "$mirror" rev-parse main)"
  run splice merge --upstream mirror --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "splice: bump vendor/a from mirror/main at ${target:0:7}" ]
  git -C "$mirror" update-ref refs/heads/main "$target^"
  splice fetch --upstream mirror vendor/a
  run splice merge --upstream mirror --bump vendor/a
  [ "$output" = "ok   vendor/a: nothing to bump -- the fetched 'mirror/main' is older than the synced commit" ]
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
  [ "$(git rev-parse refs/splices/upstream-fork/heads/main)" = "$(git -C "$fork" rev-parse main)" ]
}

@test "fetch: says which branch moved in each upstream, by that upstream's default branch" {
  scenario_several_upstreams "$monorepo" "$upstream"
  git -C "$fork" branch -m main trunk
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.fork.url "$fork"
  git config --file vendor/a/.splice upstream.fork.default-branch trunk
  add_upstream vendor/a fork "$fork" origin
  splice fetch
  seed_bare_repo "$fork" "moved" trunk
  run splice fetch
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ok   vendor/a fetched from origin" ]
  [[ "${lines[1]}" == "ok   vendor/a fetched from fork (trunk moved "* ]]
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
  [ "$(git rev-parse refs/splices/upstream/heads/main)" = "$(git -C "$upstream" rev-parse main)" ]
}

@test "--upstream: push compares with the upstream it names, not the default one" {
  scenario_several_upstreams "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "$fork" origin
  splice fetch >/dev/null
  echo "local" >>vendor/a/file.txt
  git commit -q -am "local"
  run splice push --upstream fork vendor/a
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   vendor/a: upstream has commits this branch lacks" ]
  run splice status
  [ "$output" = "$(printf 'On branch main\n\n  ahead 1  vendor/a -> origin/main')" ]
}

@test "upstreams: a splice below follows the default branch its upstreams above agree on, even without a default-upstream" {
  scenario_outer_fork "$monorepo" "$upstream"
  cd "$monorepo"
  add_upstream vendor/a fork "${upstream%.git}-fork.git"
  run splice status vendor/a/b
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'On branch main\n\n  up to date  vendor/a/b')" ]
}

@test "upstreams: a splice below refuses to guess when the upstreams above have different default branches and none is the default" {
  scenario_outer_fork "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.fork.default-branch trunk
  add_upstream vendor/a fork "${upstream%.git}-fork.git"
  for command in "status vendor/a/b" "pull vendor/a/b" "merge vendor/a/b" "push vendor/a/b" "diff vendor/a/b" "log vendor/a/b"; do
    # shellcheck disable=SC2086 # the command and its arguments
    run splice $command
    [ "$status" -eq 1 ]
    [ "$output" = "!!   vendor/a/b follows the default branch of vendor/a, whose upstreams have different default branches (origin: main, fork: trunk), but no default -- commit one: git config --file vendor/a/.splice splice.default-upstream <name>" ]
  done
  run splice clone "$upstream" vendor/a/c
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a/c follows the default branch of vendor/a, whose upstreams have different default branches (origin: main, fork: trunk), but no default -- commit one: git config --file vendor/a/.splice splice.default-upstream <name>" ]
  [ ! -e vendor/a/c ]
  make_bare_repo "$BATS_TEST_TMPDIR/empty.git"
  mkdir vendor/a/d && echo d >vendor/a/d/file.txt
  git add vendor/a/d && git commit -q -m "add vendor/a/d"
  run splice init vendor/a/d "$BATS_TEST_TMPDIR/empty.git"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a/d follows the default branch of vendor/a, whose upstreams have different default branches (origin: main, fork: trunk), but no default -- commit one: git config --file vendor/a/.splice splice.default-upstream <name>" ]
  [ ! -e vendor/a/d/.splice ]
}

@test "pull --all: a splice below uses the upstreams its .splice names after the pull above, not before" {
  scenario_outer_fork "$monorepo" "$upstream"
  local b_fork="$BATS_TEST_TMPDIR/upstream-b-fork.git" work="$BATS_TEST_TMPDIR/a"
  git clone -q "$upstream" "$work"
  (
    cd "$work"
    git config user.name Test && git config user.email test@example.com
    add_upstream b fork "$b_fork" fork
    git push -q origin HEAD:main
  )
  cd "$monorepo"
  run splice pull --all
  [ "$status" -eq 0 ]
  [ "${lines[3]}" = "ok   vendor/a/b fetched from fork" ]
  [ "$(splice_config vendor/a/b commit)" = "$(git -C "$b_fork" rev-parse main)" ]
}

@test "merge --all: a splice below whose new upstream, from the merge above, isn't fetched yet says so" {
  scenario_outer_fork "$monorepo" "$upstream"
  local b_fork="$BATS_TEST_TMPDIR/upstream-b-fork.git" work="$BATS_TEST_TMPDIR/a"
  git clone -q "$upstream" "$work"
  (
    cd "$work"
    git config user.name Test && git config user.email test@example.com
    add_upstream b fork "$b_fork" fork
    git push -q origin HEAD:main
  )
  cd "$monorepo"
  splice fetch
  run splice merge --all
  [ "$status" -eq 1 ]
  [ "${lines[1]}" = "??   vendor/a/b: not fetched yet -- run 'git splice fetch vendor/a/b' first" ]
  splice fetch vendor/a/b
  run splice merge vendor/a/b
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a/b commit)" = "$(git -C "$b_fork" rev-parse main)" ]
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

@test "pull --upstream: a selected splice below gets the synced commit the pull above moves it to, from any of its upstreams" {
  scenario_outer_fork "$monorepo" "$upstream"
  local b_origin="$BATS_TEST_TMPDIR/upstream-b.git" b_fork="$BATS_TEST_TMPDIR/upstream-b-fork.git" work="$BATS_TEST_TMPDIR/a-fork"
  seed_bare_repo "$b_origin" "b origin only" main origin.txt
  git clone -q "$fork" "$work"
  (
    cd "$work"
    git config user.name Test && git config user.email test@example.com
    add_upstream b fork "$b_fork" origin
    splice pull b
    git push -q origin HEAD:main
  )
  cd "$monorepo"
  add_upstream vendor/a fork "$fork" origin
  add_upstream vendor/a/b fork "$b_fork" origin
  run splice pull --upstream fork --all
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a/b commit)" = "$(git -C "$b_fork" rev-parse main)" ]
}
