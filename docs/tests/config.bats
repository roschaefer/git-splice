setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load '../09-scenarios/05-nested-splices/01-nested-splices/02-three-levels/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  upstream_b="$BATS_TEST_TMPDIR/upstream-b.git"
  upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  export CONFIG_LOG="$BATS_TEST_TMPDIR/hooks.log"
  payload="$BATS_TEST_TMPDIR/checkpoint.json"
}

commit_config() {
  git add -- "$@"
  git commit -qm 'configure splice'
}

simple_splice() {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" seed
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" vendor/a
  cd "$monorepo"
}

@test "configuration: committed defaults ignore worktree and index edits and CLI wins" {
  simple_splice
  git config -f .spliceconfig splice.messageTemplate 'root: {command} {path}'
  commit_config .spliceconfig
  git config -f .spliceconfig splice.messageTemplate 'uncommitted'
  git add .spliceconfig
  run splice status vendor/a
  [ "$status" -eq 0 ]
  git reset -q HEAD -- .spliceconfig
  seed_bare_repo "$upstream" update
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = 'root: pull vendor/a' ]
  seed_bare_repo "$upstream" next
  run splice pull --message-template 'explicit: {path}' vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = 'explicit: vendor/a' ]
  seed_bare_repo "$upstream" again
  run splice pull -m 'explicit message' vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = 'explicit message' ]
}

@test "configuration: nested command sections override shared defaults for inner splices" {
  scenario_three_levels "$monorepo" "$upstream"
  cd "$monorepo"
  git config -f .spliceconfig splice.messageTemplate 'root: {path}'
  git config -f vendor/a/.spliceconfig splice.messageTemplate 'outer: {path}'
  git config -f vendor/a/b/.spliceconfig splice.messageTemplate 'shared: {path}'
  git config -f vendor/a/b/.spliceconfig splice.pull.messageTemplate 'inner: {path}'
  commit_config .spliceconfig vendor/a/.spliceconfig vendor/a/b/.spliceconfig
  seed_bare_repo "$upstream_c" update
  run splice pull vendor/a/b/c
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = 'inner: vendor/a/b/c' ]
}

@test "configuration: scoped recursive defaults schedule children and fold without affecting siblings" {
  scenario_three_levels "$monorepo" "$upstream"
  cd "$monorepo"
  git config -f vendor/a/.spliceconfig splice.pull.recursive true
  commit_config vendor/a/.spliceconfig
  seed_bare_repo "$upstream_b" 'b update'
  seed_bare_repo "$upstream_c" 'c update'
  local start
  start="$(git rev-parse HEAD)"
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a/b/c commit)" = "$(git -C "$upstream_c" rev-parse main)" ]
  [ "$(git rev-list --count "$start..HEAD")" = 1 ]
}

@test "configuration: inherited hooks run in scope and receive only their subtree" {
  scenario_three_levels "$monorepo" "$upstream"
  cd "$monorepo"
  git config -f .spliceconfig splice.fetch.exec 'jq -r '"'"'"root " + .hook_scope'"'"' >>"$CONFIG_LOG"'
  git config -f vendor/a/.spliceconfig splice.fetch.exec 'jq -r '"'"'.event.fetched[].path'"'"' >>"$CONFIG_LOG"; pwd >>"$CONFIG_LOG"'
  git config -f vendor/a/b/.spliceconfig splice.fetch.exec 'jq -r '"'"'"inner " + .hook_scope'"'"' >>"$CONFIG_LOG"'
  commit_config .spliceconfig vendor/a/.spliceconfig vendor/a/b/.spliceconfig
  run splice fetch --all
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$CONFIG_LOG")" = 'root ' ]
  [ "$(tail -n 1 "$CONFIG_LOG")" = 'inner vendor/a/b' ]
  [ "$(sed -n '5p' "$CONFIG_LOG")" = "$monorepo/vendor/a" ]
  ! grep -q '^vendor/z$' "$CONFIG_LOG"
}

@test "configuration: empty nested exec clears ancestors and explicit exec replaces configured hooks" {
  simple_splice
  git config -f .spliceconfig splice.fetch.exec 'echo root >>"$CONFIG_LOG"'
  git config -f vendor/a/.spliceconfig splice.fetch.exec ''
  commit_config .spliceconfig vendor/a/.spliceconfig
  run splice fetch vendor/a
  [ "$status" -eq 0 ]
  [ ! -e "$CONFIG_LOG" ]
  run splice fetch --exec 'cat >/dev/null; echo cli >>"$CONFIG_LOG"' vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat "$CONFIG_LOG")" = cli ]
}

@test "configuration: continuation finishes remaining hooks without rerunning stopped handlers" {
  simple_splice
  git config -f .spliceconfig splice.fetch.exec 'echo root >>"$CONFIG_LOG"; cat; exit 1'
  git config -f vendor/a/.spliceconfig splice.fetch.exec 'echo child >>"$CONFIG_LOG"; cat; exit 1'
  commit_config .spliceconfig vendor/a/.spliceconfig
  run bash -c '"$1" fetch vendor/a >"$2"' _ "$ENTRYPOINT" "$payload"
  [ "$status" -eq 1 ]
  jq -e '.hook_scope == "" and (.continuation.pending_hooks | length == 1)' "$payload"
  run bash -c '"$1" fetch --continue-from "$2" >"$2.next"' _ "$ENTRYPOINT" "$payload"
  [ "$status" -eq 1 ]
  jq -e '.hook_scope == "vendor/a" and (.event.fetched | length == 1)' "$payload.next"
  mv "$payload.next" "$payload"
  run splice fetch --continue-from "$payload"
  [ "$status" -eq 0 ]
  [ "$(cat "$CONFIG_LOG")" = $'root\nchild' ]
}

@test "configuration: hooks introduced upstream run before its checkout and become scoped defaults" {
  simple_splice
  local work="$BATS_TEST_TMPDIR/work"
  git clone -q "$upstream" "$work"
  git -C "$work" config user.name Test
  git -C "$work" config user.email test@example.com
  git -C "$work" config -f .spliceconfig splice.pull.exec 'payload=$(cat); printf "%s\n" "$payload" | jq -r .event.checkpoint >>"$CONFIG_LOG"; printf "%s\n" "$payload"; exit 1'
  git -C "$work" config -f .spliceconfig splice.pull.messageTemplate 'incoming: {path}'
  git -C "$work" add .spliceconfig
  git -C "$work" commit -qm configure
  git -C "$work" push -q origin main
  run bash -c '"$1" pull vendor/a >"$2"' _ "$ENTRYPOINT" "$payload"
  [ "$status" -eq 1 ]
  jq -e '.hook_scope == "vendor/a" and .event.checkpoint == "after-fetch"' "$payload"
  [ ! -e vendor/a/.spliceconfig ]
  run bash -c '"$1" pull --continue-from "$2" >"$2.next"' _ "$ENTRYPOINT" "$payload"
  [ "$status" -eq 1 ]
  jq -e '.event.checkpoint == "after-merge"' "$payload.next"
  [ -f vendor/a/.spliceconfig ]
  mv "$payload.next" "$payload"
  run splice pull --continue-from "$payload"
  [ "$status" -eq 0 ]
  [ "$(cat "$CONFIG_LOG")" = $'after-fetch\nafter-merge' ]
}

@test "configuration: changed committed configuration invalidates continuation" {
  simple_splice
  git config -f .spliceconfig splice.fetch.exec 'cat; exit 1'
  commit_config .spliceconfig
  run bash -c '"$1" fetch vendor/a >"$2"' _ "$ENTRYPOINT" "$payload"
  [ "$status" -eq 1 ]
  git config -f .spliceconfig splice.fetch.exec true
  commit_config .spliceconfig
  run splice fetch --continue-from "$payload"
  [ "$status" -eq 1 ]
  [[ "$output" == *'splice configuration changed'* ]]
}

@test "configuration: invalid booleans and templates identify the committed config before writes" {
  simple_splice
  git config -f .spliceconfig splice.pull.recursive perhaps
  commit_config .spliceconfig
  local before
  before="$(git rev-parse HEAD)"
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *'.spliceconfig: invalid boolean'* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
  git config -f .spliceconfig splice.pull.recursive false
  git config -f .spliceconfig splice.messageTemplate '{typo}'
  commit_config .spliceconfig
  before="$(git rev-parse HEAD)"
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *'.spliceconfig: invalid messageTemplate'* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "configuration: an inner false recursive default stops descent unless CLI overrides it" {
  scenario_three_levels "$monorepo" "$upstream"
  cd "$monorepo"
  git config -f vendor/a/.spliceconfig splice.pull.recursive true
  git config -f vendor/a/b/.spliceconfig splice.pull.recursive false
  commit_config vendor/a/.spliceconfig vendor/a/b/.spliceconfig
  seed_bare_repo "$upstream_c" 'c update'
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/b/c/file.txt)" = 'c seed' ]
  run splice pull --recursive vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/b/c/file.txt)" = $'c seed\nc update' ]
}

@test "configuration: a parent pull changes a child's branch without changing its splice file" {
  scenario_three_levels "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" 'b release' release
  seed_bare_repo "$upstream_c" 'c release' release
  local work="$BATS_TEST_TMPDIR/work"
  git clone -q "$upstream" "$work"
  git -C "$work" config user.name Test
  git -C "$work" config user.email test@example.com
  git -C "$work" config -f b/.spliceconfig splice.pull.branch release
  git -C "$work" add b/.spliceconfig
  git -C "$work" commit -qm 'configure b release'
  git -C "$work" push -q origin main
  cd "$monorepo"
  run splice pull --recursive vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/b/file.txt)" = $'b seed\nb release' ]
  [ "$(splice_config vendor/a/b commit)" = "$(git -C "$upstream_b" rev-parse release)" ]
}

@test "configuration: a handler from a fetched tag emits clean continuation before checkout" {
  simple_splice
  local work="$BATS_TEST_TMPDIR/work"
  git clone -q "$upstream" "$work"
  git -C "$work" config user.name Test
  git -C "$work" config user.email test@example.com
  git -C "$work" config -f .spliceconfig splice.fetch.exec 'cat; exit 1'
  git -C "$work" add .spliceconfig
  git -C "$work" commit -qm configure
  git -C "$work" tag v2
  git -C "$work" push -q origin main v2
  git config -f vendor/a/.splice upstream.origin.default-pin v2
  git add vendor/a/.splice
  git commit -qm 'pin version two'
  run bash -c '"$1" fetch vendor/a >"$2"' _ "$ENTRYPOINT" "$payload"
  [ "$status" -eq 1 ]
  jq -e '.hook_scope == "vendor/a" and .event.checkpoint == "after-fetch"' "$payload"
  [ ! -e vendor/a/.spliceconfig ]
  run splice fetch --continue-from "$payload"
  [ "$status" -eq 0 ]
}

@test "configuration: boolean defaults distinguish an empty value from a valueless key like Git" {
  scenario_three_levels "$monorepo" "$upstream"
  cd "$monorepo"
  git config -f .spliceconfig splice.pull.recursive ''
  commit_config .spliceconfig
  seed_bare_repo "$upstream_c" 'c update'
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/b/c/file.txt)" = 'c seed' ]
  printf '[splice "pull"]\n\trecursive\n' >.spliceconfig
  commit_config .spliceconfig
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/b/c/file.txt)" = $'c seed\nc update' ]
}
