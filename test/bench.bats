# bench/run.sh times commands on the fixture bench/setup.sh builds; these
# tests pin down the fixture's shape, which the timings depend on.

setup() {
  # A space and a "%" in the path must survive the ext:: upstream URLs.
  fixture="$BATS_TEST_TMPDIR/bench dir 100%"
  BENCH_SPLICES=2 BENCH_COMMITS=4 BENCH_LATENCY=0 \
    "$BATS_TEST_DIRNAME/../bench/setup.sh" "$fixture"
  cd "$fixture/monorepo"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
}

@test "bench fixture: one splice per upstream, reached through the delayed ext:: transport" {
  [ "$(git ls-files '*/.splice' | tr '\n' ' ')" = "packages/sub1/.splice packages/sub2/.splice " ]
  [[ "$(git config --file packages/sub1/.splice splice.url)" == "ext::sh -c sleep% 0;% exec% %S% "* ]]
  [ -z "$(git remote)" ]
  run "$BATS_TEST_DIRNAME/../git-splice" fetch
  [ "$status" -eq 0 ]
}

@test "bench fixture: each upstream holds the monorepo's push from halfway, and the monorepo changed since" {
  local sub
  for sub in sub1 sub2; do
    run git log --format=%s "refs/splices/packages/$sub/main"
    [[ "$output" == *"$sub: round 2"* ]]
    [[ "$output" != *"$sub: round 3"* ]]
  done
  run git log --format=%s -- packages/sub1
  [[ "$output" == *"sub1: round 4"* ]]
  run "$BATS_TEST_DIRNAME/../git-splice" status
  [[ "${lines[0]}" == *"(push)" ]]
}

@test "bench fixture: marked complete only once setup has finished" {
  [ -e "$fixture/complete" ]

  # A setup that fails after the monorepo exists must leave no marker, so
  # bench/run.sh rebuilds it instead of timing a half-built fixture.
  local broken="$BATS_TEST_TMPDIR/broken"
  BENCH_SPLICES=1 BENCH_COMMITS=not-a-number BENCH_LATENCY=0 \
    run "$BATS_TEST_DIRNAME/../bench/setup.sh" "$broken"
  [ "$status" -ne 0 ]
  [ -d "$broken/monorepo" ]
  [ ! -e "$broken/complete" ]
}
