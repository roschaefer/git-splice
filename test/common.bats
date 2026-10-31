setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load 'scenarios/01-everyday-sync/02-up-to-date/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/01-pull-ahead/setup'
  load 'scenarios/06-rewritten-history/03-diverged-unrelated-history/setup'
  load 'scenarios/04-upstreams/03-shared-remote-url/setup'
  load 'scenarios/05-nested-splices/01-nested-splices/setup'
  load 'scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/setup'
  load 'scenarios/03-branches-and-teamwork/01-feature-branch-unchanged/01-feature-branch-changed/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "discovery: finds every folder with a committed .splice" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p untracked && echo x >untracked/.splice
  [ "$(discovered_splices)" = "vendor/a vendor/b" ]
}

@test "discovery: is empty without .splice files" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  [ "$(discovered_splices)" = none ]
}

@test "discovery: finds a splice nested in another" {
  scenario_nested_splices "$monorepo" "$upstream"
  cd "$monorepo"
  [ "$(discovered_splices)" = "vendor/a vendor/a/b" ]
}

@test "discovery: a file name with a newline doesn't make a splice" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p $'notes\nphantom'
  echo x >$'notes\nphantom/.splice'
  git add . && git commit -q -m "a file name with a newline"
  run splice status
  [ "$status" -eq 1 ]
  [[ "$output" == *"isn't supported as a splice path yet"* ]]
  [[ "$output" != *"'phantom'"* ]]
}

@test "discovery: matches .splice literally, not as a pattern" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p notes && echo x >notes/xsplice && echo x >vendor/a/-splice
  git add . && git commit -q -m "files whose names only resemble .splice"
  [ "$(discovered_splices)" = "vendor/a" ]
}

@test "discovery: reads HEAD, not the index" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  git rm -q --cached vendor/b/.splice
  mkdir -p vendor/c && echo "[splice]" >vendor/c/.splice && git add vendor/c/.splice
  [ "$(discovered_splices)" = "vendor/a vendor/b" ]
}

@test "discovery: refuses a path that can't be part of a ref" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p "my lib" && echo "[splice]" >"my lib/.splice"
  git add "my lib" && git commit -q -m "a splice by hand"
  run splice status
  [ "$status" -eq 1 ]
  [[ "$output" == *"'my lib' isn't supported as a splice path yet"* ]]
}

@test "discovery: refuses a .splice at the repository root" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  echo x >.splice
  git add .splice
  git commit -q -m "a .splice at the root"
  run splice status
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a folder"* ]]
}

@test "paths: splicing in or out needs paths or --all" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  run splice push
  [ "$status" -eq 1 ]
  [[ "$output" == *"which splice?"*"vendor/a vendor/b"* ]]
  run splice push --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a"*"vendor/b"* ]]
}

@test "paths: looking covers every splice by default" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  run splice status
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a"*"vendor/b"* ]]
}

@test "paths: normalizes and deduplicates paths, and refuses others" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  run splice status ./vendor/b/ vendor/b
  [ "$status" -eq 0 ]
  [ "$(grep -c vendor/b <<<"$output")" -eq 1 ]
  [[ "$output" != *vendor/a* ]]
  run splice push vendor
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a splice: vendor"* ]]
}

@test "paths: paths and --all together are refused" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  run splice push --all vendor/a
  [ "$status" -eq 1 ]
}

@test "options: refuses options the command doesn't take, and -- ends them" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice status --merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option: --merge"* ]]
  run splice status -- --odd-path
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a splice: --odd-path"* ]]
}

@test "options: -m takes its message in each of git's forms, and several join as paragraphs, as in git commit" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  splice merge -m one -mtwo --message three --message=four vendor/a >/dev/null
  [ "$(git log -1 --format=%B)" = "one

two

three

four" ]
}

@test "options: -m needs a message, and only commands that commit take it" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge -m "" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"-m needs a message"* ]]
  run splice push --message=x vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option: --message"* ]]
}

@test "state file: a command stops when it can't write it, e.g. on a full disk" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before synced
  before="$(git rev-parse HEAD)"
  synced="$(splice_config vendor/a commit)"
  find .git/objects -type d -exec chmod a-w {} +
  run splice merge --bump vendor/a
  find .git/objects -type d -exec chmod u+w {} +
  [ "$status" -ne 0 ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ "$(git config --file vendor/a/.splice splice.commit)" = "$synced" ]
}

@test "default branch: only the monorepo's default branch maps to default-branch" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  [[ "$(splice status vendor/a)" != *"->"* ]]
  git config --file vendor/a/.splice upstream.origin.default-branch master
  git commit -q -am "upstream calls it master"
  [[ "$(splice status vendor/a)" == *"vendor/a -> master"* ]]
  git switch -q -c feature
  [[ "$(splice status vendor/a)" != *"->"* ]]
}

@test "guidance on unrelated history quotes names with shell metacharacters" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge vendor/a
  [[ "$output" == *"git splice push --force -- vendor/a"* ]]
  [[ "$output" == *"git rm -q -- vendor/a/.splice"* ]]
  git mv vendor/a "x;id"
  git commit -q -m "a name for the shell to run"
  run splice merge "x;id"
  [[ "$output" == *"git splice push --force -- 'x;id'"* ]]
  git mv "x;id" "it's"
  git commit -q -m "a name for the shell to end its quote"
  run splice merge "it's"
  [[ "$output" == *"git splice push --force -- 'it'\\''s'"* ]]
  git mv "it's" ./-foo
  git commit -q -m "a name for git to read as an option"
  run splice merge -- -foo
  [[ "$output" == *"git rm -r -q -- -foo"* ]]
  [[ "$output" == *"git splice clone -- "*" -foo"* ]]
}

# Commits splice k naming upstream URL $1 and sets UPSTREAM_KEY to the key
# `git splice fetch` records for it. The fetch fails after that, as no
# protocol is allowed: none of these URLs is real.
record_upstream_key() {
  local output
  mkdir -p k
  git config --file k/.splice splice.id 0123456789abcdef
  git config --file k/.splice upstream.origin.url "$1"
  git add k/.splice
  git commit -q --allow-empty -m "k names $1"
  output="$(GIT_ALLOW_PROTOCOL=none splice fetch k 2>&1)" || true
  UPSTREAM_KEY="$(splice key k 2>/dev/null)" || {
    printf '%s\n' "$output"
    return 1
  }
}

# Checks that upstream URL $1 gets the keys $2..., in order, each once the
# one before it is taken. Recording it also checks that each is a valid key:
# `git splice key` refuses to read others.
assert_candidates() {
  local url="$1" expected
  shift
  for expected in "$@"; do
    record_upstream_key "$url"
    echo "$url -> $UPSTREAM_KEY, expected $expected" >&2
    [ "$UPSTREAM_KEY" = "$expected" ]
    git update-ref "refs/splices/$UPSTREAM_KEY" HEAD
    git config --local --remove-section "splice.$UPSTREAM_KEY"
  done
  git for-each-ref --format='delete %(refname)' refs/splices/ | git update-ref --stdin
}

@test "upstream key: the URL's last component first, then more of its path, up to the host" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  assert_candidates https://github.com/x/lib.git lib x-lib github.com-x-lib
  assert_candidates git@github.com:x/lib.git lib x-lib github.com-x-lib
  assert_candidates ssh://git@host:2222/x/lib lib x-lib 2222-x-lib host-2222-x-lib
  assert_candidates host:lib lib host-lib
  assert_candidates /srv/git/lib/ lib git-lib srv-git-lib
  assert_candidates ../lib.git lib
}

@test "upstream key: lower case, with what a key can't hold replaced by -" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  assert_candidates https://host/Org/My_Lib.git my_lib org-my_lib host-org-my_lib
  assert_candidates "https://host/a b~c" a-b-c host-a-b-c
  assert_candidates https://host/x.lock x-lock host-x-lock
  assert_candidates https://host/.hidden..name hidden.name host-.hidden.name
}

@test "upstream key: falls back to 'upstream' when no part of the URL is usable" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  assert_candidates https://host/%%% host
  assert_candidates / upstream
  assert_candidates "%%%" upstream
}

@test "upstream key: keeps the end of a long name" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  record_upstream_key "https://host/$(printf 'a%.0s' {1..300})-end"
  [ "${#UPSTREAM_KEY}" -eq 60 ]
  [[ "$UPSTREAM_KEY" == *-end ]]
}

@test "upstream key: lower-case letters, digits, '.', '_' and '-' only" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  local key
  for key in lib lib-2 my_lib.v2; do
    splice key vendor/a "$key" >/dev/null
  done
  for key in Lib -lib lib. a/b a..b "$(printf 'a%.0s' {1..65})"; do
    run splice key vendor/a -- "$key"
    [ "$status" -eq 1 ]
    [[ "$output" == *"isn't a valid key"* ]]
  done
}

@test "upstream key: none for an upstream never fetched" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir k
  git config --file k/.splice splice.id 0123456789abcdef
  git config --file k/.splice upstream.origin.url https://github.com/x/lib.git
  git add k/.splice
  git commit -q -m "k names an upstream"
  run splice key k
  [ "$status" -eq 1 ]
  [[ "$output" == *"its upstream has no key yet"* ]]
  [ -z "$(git config --local --get-regexp '^splice\.' || true)" ]
}

@test "upstream key: is recorded in the repository's config, and reused" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  record_upstream_key https://github.com/x/lib.git
  [ "$UPSTREAM_KEY" = lib ]
  [ "$(git config --local splice.lib.url)" = https://github.com/x/lib.git ]
  record_upstream_key https://github.com/x/lib.git
  [ "$UPSTREAM_KEY" = lib ]
  [ "$(git config --local --get-all splice.lib.url | wc -l)" -eq 1 ]
}

@test "upstream key: a taken name gets more of the URL, not a number" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  record_upstream_key https://github.com/x/lib.git
  [ "$UPSTREAM_KEY" = lib ]
  record_upstream_key https://gitlab.com/y/lib.git
  [ "$UPSTREAM_KEY" = y-lib ]
  record_upstream_key https://example.com/y/lib.git
  [ "$UPSTREAM_KEY" = example.com-y-lib ]
}

@test "upstream key: a number only once every name from the URL is taken" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  record_upstream_key https://host/lib
  record_upstream_key https://host/lib.git
  [ "$UPSTREAM_KEY" = host-lib ]
  record_upstream_key https://host/lib/
  [ "$UPSTREAM_KEY" = host-lib-2 ]
}

@test "upstream key: URLs differing only in case get keys that differ in more than case" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  record_upstream_key ssh://host/Org/Lib
  [ "$UPSTREAM_KEY" = lib ]
  record_upstream_key ssh://host/org/lib
  [ "$UPSTREAM_KEY" = org-lib ]
}

@test "upstream key: skips a key whose refs are left over" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git update-ref refs/splices/lib/heads/main HEAD
  record_upstream_key https://github.com/x/lib.git
  [ "$UPSTREAM_KEY" = x-lib ]
}

@test "upstream key: skips a key a ref is named like, which its refs would conflict with" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git update-ref refs/splices/lib HEAD
  record_upstream_key https://github.com/x/lib.git
  [ "$UPSTREAM_KEY" = x-lib ]
}

@test "upstream key: refs of a longer key don't take a shorter one" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git update-ref refs/splices/libfoo/heads/main HEAD
  record_upstream_key https://github.com/x/lib.git
  [ "$UPSTREAM_KEY" = lib ]
}

@test "upstream key: sees a key another command recorded since this one read the config" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  local read_once="$BATS_TEST_TMPDIR/read-once"
  stub_git "
    if [[ \"\$*\" == *'--get-regexp ^splice'* && ! -e '$read_once' ]]; then
      touch '$read_once'
      \"\$real_git\" \"\$@\"
      rc=\$?
      \"\$real_git\" config --local splice.lib.url https://gitlab.com/y/lib.git
      exit \$rc
    fi"
  record_upstream_key https://github.com/x/lib.git
  [ "$UPSTREAM_KEY" = x-lib ]
  [ "$(git config --local splice.lib.url)" = https://gitlab.com/y/lib.git ]
}

@test "upstream key: waits for another command's lock" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir .git/splice-keys.lock
  (sleep 0.3 && rmdir .git/splice-keys.lock) &
  record_upstream_key https://github.com/x/lib.git
  wait
  [ "$UPSTREAM_KEY" = lib ]
  [ ! -e .git/splice-keys.lock ]
}

@test "upstream key: names a lock that stays, and gives up" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  mkdir .git/splice-keys.lock
  run record_upstream_key https://github.com/x/lib.git
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   another git splice is recording an upstream key -- if none is running, remove $monorepo/.git/splice-keys.lock"* ]]
  [ -z "$(git config --local --get-regexp '^splice\.' || true)" ]
}

@test "upstream key: releases the lock when it fails" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  stub_git '[[ "$1 $2 $3" != "config --local splice.lib.url" ]] || exit 1'
  run record_upstream_key https://github.com/x/lib.git
  [ "$status" -eq 1 ]
  [ ! -e .git/splice-keys.lock ]
}

@test "config check: refuses a key that isn't valid, e.g. one with upper case" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config --local splice.Lib.url https://github.com/x/lib.git
  run record_upstream_key https://github.com/x/lib.git
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   splice.Lib.url in the repository's config: 'Lib' isn't a valid key -- rename it: git config --local --rename-section splice.Lib splice.<new-key>"* ]]
}

@test "config check: refuses a key with several URLs" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config --local --add splice.lib.url https://github.com/x/lib.git
  git config --local --add splice.lib.url https://gitlab.com/y/lib.git
  run record_upstream_key https://github.com/x/lib.git
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   splice.lib.url is set more than once in the repository's config -- keep one: git config --local --edit"* ]]
}

@test "config check: refuses a URL with several keys" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config --local splice.lib.url https://github.com/x/lib.git
  git config --local splice.x-lib.url https://github.com/x/lib.git
  run record_upstream_key https://github.com/x/lib.git
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   keys 'lib' and 'x-lib' both name https://github.com/x/lib.git in the repository's config -- remove one: git config --local --remove-section splice.x-lib"* ]]
}

@test "config check: refuses an empty URL" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config --local splice.lib.url ""
  run record_upstream_key https://github.com/x/lib.git
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   splice.lib.url in the repository's config is empty -- remove it: git config --local --remove-section splice.lib"* ]]
}

@test "config check: the printed commands fix the config" {
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config --local splice.Lib.url https://github.com/x/lib.git
  git config --local splice.x-lib.url https://github.com/x/lib.git
  git config --local --rename-section splice.Lib splice.lib
  git config --local --remove-section splice.x-lib
  record_upstream_key https://github.com/x/lib.git
  [ "$UPSTREAM_KEY" = lib ]
}

@test "discovery: refuses a .splice without an id" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice --unset splice.id
  git commit -q -am "no id"
  run splice status
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a/.splice has no id" ]
}

@test "discovery: refuses a .splice without an upstream, or with an empty URL" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice --remove-section upstream.origin
  git commit -q -am "no upstream"
  run splice status
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/.splice names no upstream"* ]]
  git config --file vendor/a/.splice upstream.origin.url ""
  git commit -q -am "empty upstream URL"
  run splice status
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/.splice names no upstream"* ]]
}

@test "discovery: refuses a .splice git config can't read, with Git's message" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  printf '<<<<<<< HEAD\n' >>vendor/a/.splice
  git commit -q -am "conflict markers"
  run splice status
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/.splice can't be read (bad config line "*") -- fix it and commit it"* ]]
}

@test "discovery: refuses a .splice that git config can't read from its first line" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  { printf '<<<<<<< HEAD\n'; cat vendor/a/.splice; } >vendor/a/.splice.new
  mv vendor/a/.splice.new vendor/a/.splice
  git commit -q -am "conflict markers first"
  run splice status
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/.splice can't be read (bad config line 1 "*") -- fix it and commit it"* ]]
}

@test "discovery: reads an upstream URL with a newline in it whole" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.origin.url $'/srv/a\nb.git'
  git commit -q -am "newline in the URL"
  GIT_ALLOW_PROTOCOL=none splice fetch vendor/a >/dev/null 2>&1 || true
  [ "$(git config --local "splice.$(splice key vendor/a).url")" = $'/srv/a\nb.git' ]
}

@test "discovery: refuses a splice path that isn't valid UTF-8, naming the folder to rename" {
  [[ "$ENTRYPOINT" == */target/* ]] || skip "bash takes any bytes"
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir $'caf\xe9'
  cp vendor/a/.splice $'caf\xe9/.splice'
  git add . && git commit -q -m "a folder whose name isn't UTF-8"
  run splice status
  [ "$status" -eq 1 ]
  [[ "$output" == *"isn't valid UTF-8"* ]]
}

@test "state file: a synced commit with multibyte characters is reported, not a crash" {
  [[ "$ENTRYPOINT" == */target/* ]] || skip "bash counts bytes in a non-UTF-8 locale"
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice splice.commit "abcdefäöü"
  git commit -q -am "a synced commit edited by hand"
  run splice status
  [ "$status" -eq 0 ]
  [[ "$output" == *"synced commit abcdefä isn't here"* ]]
}
