setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load '../09-scenarios/01-everyday-sync/02-up-to-date/setup'
  load '../09-scenarios/01-everyday-sync/04-never-fetched/setup'
  load '../09-scenarios/04-upstreams/03-shared-remote-url/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "key: prints the key of the splice's upstream, for its refs" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice key vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = upstream ]
  git rev-parse --verify --quiet "refs/splices/$output/heads/main"
}

@test "key: an upstream never fetched has none yet, and asking doesn't record one" {
  scenario_never_fetched "$monorepo" "$upstream"
  cd "$monorepo"
  run splice key vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a: its upstream has no key yet -- 'git splice fetch vendor/a' records one" ]
  [ -z "$(git config --local --get-regexp '^splice\.' || true)" ]
}

@test "key: renaming moves the refs and the config entry" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "on a branch" feature/x
  cd "$monorepo"
  splice fetch >/dev/null
  run splice key vendor/a lib
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: renamed key 'upstream' to 'lib'" ]
  [ "$(git for-each-ref --format='%(refname)' refs/splices/)" = "refs/splices/lib/heads/feature/x"$'\n'"refs/splices/lib/heads/main" ]
  [ "$(git config --local splice.lib.url)" = "$upstream" ]
  [ -z "$(git config --local splice.upstream.url || true)" ]
  run "$ENTRYPOINT" status vendor/a
  [ "${lines[*]:1}" = "  up to date  vendor/a" ]
}

@test "key: a rename applies to every splice with the same URL" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  splice key vendor/a lib >/dev/null
  run splice key vendor/b
  [ "$output" = lib ]
}

@test "key: refuses an invalid key, or one that's taken" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --local splice.other.url https://example.com/other.git
  run splice key vendor/a Lib
  [ "$status" -eq 1 ]
  [[ "$output" == "!!   'Lib' isn't a valid key -- "* ]]
  run splice key vendor/a other
  [ "$status" -eq 1 ]
  [[ "$output" == "!!   key 'other' is taken -- "* ]]
  [ "$(splice key vendor/a)" = upstream ]
}

@test "key: renaming to the same key changes nothing" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice key vendor/a upstream
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: key is 'upstream' already" ]
}

@test "key: refuses a path that isn't a splice" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice key vendor
  [ "$status" -eq 1 ]
  [ "$output" = "!!   not a splice: vendor" ]
}

@test "key: --upstream names the splice's upstream, in both forms" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice key --upstream origin vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = upstream ]
  run splice key --upstream=origin vendor/a lib
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: renamed key 'upstream' to 'lib'" ]
}

@test "key: refuses an upstream the splice doesn't have, naming the one it has" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice key --upstream fork vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a has no upstream 'fork' -- its upstream is 'origin'" ]
}

@test "key: --upstream needs a name" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice key vendor/a --upstream
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --upstream needs an upstream's name" ]
  run splice key --upstream= vendor/a
  [ "$status" -eq 1 ]
}

@test "--upstream: refused by commands that don't sync with an upstream" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice clone --upstream origin "$upstream" vendor/b
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   unknown option: --upstream" ]]
  run splice init --upstream=origin vendor/b "$upstream"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   unknown option: --upstream" ]]
}

@test "key: takes the path in any spelling the other commands take" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  [ "$(splice key ./vendor/a)" = upstream ]
  [ "$(splice key vendor/a//)" = upstream ]
}

@test "key: a rename of a key another command renamed meanwhile fails, and releases the lock" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  local read_once="$BATS_TEST_TMPDIR/read-once"
  stub_git "
    if [[ \"\$*\" == *'--get-regexp ^splice'* && ! -e '$read_once' ]]; then
      touch '$read_once'
      \"\$real_git\" \"\$@\"
      rc=\$?
      \"\$real_git\" config --local --rename-section splice.upstream splice.other
      exit \$rc
    fi"
  run splice key vendor/a lib
  [ "$status" -eq 1 ]
  [ "$output" = "!!   key 'upstream' is gone -- run 'git splice key' again" ]
  [ ! -e .git/splice-keys.lock ]
}

@test "key: a rename stops, changing nothing, when it can't list the key's refs" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  stub_git 'if [[ "$*" == *"for-each-ref --format=%(refname) %(objectname)"* ]]; then exit 1; fi'
  run splice key vendor/a lib
  [ "$status" -eq 1 ]
  [ "$(splice key vendor/a)" = upstream ]
  [ -n "$(git for-each-ref refs/splices/upstream/)" ]
  [ ! -e .git/splice-keys.lock ]
}

@test "fetch: refuses to record a numbered key longer than 64 characters, and takes one recorded by hand" {
  local name
  name="$(printf 'a%.0s' {1..60})"
  upstream="$BATS_TEST_TMPDIR/$name.git"
  scenario_never_fetched "$monorepo" "$upstream"
  cd "$monorepo"
  {
    printf '[splice "%s"]\n\turl = https://example.com/0.git\n' "$name"
    for n in $(seq 2 999); do
      printf '[splice "%s-%s"]\n\turl = https://example.com/%s.git\n' "$name" "$n" "$n"
    done
  } >>.git/config
  run splice fetch vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   couldn't make a valid key for $upstream -- record one yourself: git config --local splice.<key>.url $upstream" ]
  [ -z "$(git config --local "splice.$name-1000.url" || true)" ]
  git config --local splice.mine.url "$upstream"
  splice fetch vendor/a >/dev/null
  [ "$(splice key vendor/a)" = mine ]
  git rev-parse --verify --quiet refs/splices/mine/heads/main
}

# Serves the upstream through Git's ext:: transport, after renaming the key
# the way 'git splice key' in another worktree would: between the lookup of
# the key and the write of the refs under it.
rename_key_while_serving() {
  local new="$1"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/rename-then-serve" <<SCRIPT
#!/bin/sh
(unset GIT_DIR GIT_WORK_TREE; cd "$monorepo" && "$ENTRYPOINT" key vendor/a $new) >&2
unset GIT_DIR GIT_WORK_TREE
exec git "\${1#git-}" "\$2"
SCRIPT
  chmod +x "$BATS_TEST_TMPDIR/bin/rename-then-serve"
  git config --local protocol.ext.allow always
  git config --local "url.ext::rename-then-serve %S $upstream.insteadOf" "$upstream"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "key: a fetch racing a rename refuses, and the next fetch updates the renamed key" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  splice fetch >/dev/null
  seed_bare_repo "$upstream" "on a branch" feature/x
  rename_key_while_serving lib
  run splice fetch vendor/a
  [ "$status" -ne 0 ]
  [ "${lines[-1]}" = "!!   upstream key 'upstream' was renamed while fetching -- run the command again" ]
  git config --local --unset "url.ext::rename-then-serve %S $upstream.insteadOf"
  splice fetch vendor/a >/dev/null
  git rev-parse --verify --quiet refs/splices/lib/heads/feature/x
}

@test "key: a push racing a rename refuses, and asks to fetch" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  echo change >vendor/a/new.txt
  git add vendor/a/new.txt
  git commit -qm "change vendor/a"
  rename_key_while_serving lib
  run splice push vendor/a
  [ "$status" -ne 0 ]
  [ "${lines[1]}" = "!!   vendor/a: pushed, but its upstream key was renamed meanwhile -- run 'git splice fetch vendor/a'" ]
  git config --local --unset "url.ext::rename-then-serve %S $upstream.insteadOf"
  splice fetch vendor/a >/dev/null
  [ "$(git rev-parse refs/splices/lib/heads/main)" = "$(git -C "$upstream" rev-parse main)" ]
}
