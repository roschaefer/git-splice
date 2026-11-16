setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load '../09-scenarios/01-everyday-sync/02-up-to-date/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  saved="$BATS_TEST_TMPDIR/paused.json"
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
}

@test "continuation: pull saves downloads without merging and resumes without refetching" {
  seed_bare_repo "$upstream" "upstream change"
  before="$(git rev-parse HEAD)"
  run splice pull vendor/a --pause-after after-fetch --save-to "$saved"
  [ "$status" -eq 75 ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -s "$saved" ]
  cp "$saved" "$saved.stale"
  run splice pull --continue-from "$saved"
  [ "$status" -eq 0 ]
  [[ "$output" != *" fetched"* ]]
  [[ "$output" == *"vendor/a: pulled"* ]]
  [ "$(git show HEAD:vendor/a/file.txt | tail -1)" = "upstream change" ]
  [ ! -e "$saved" ]
  run splice pull --continue-from "$saved.stale"
  [ "$status" -eq 1 ]
  [[ "$output" == *"repository state changed"* ]]
}

@test "continuation: changed tracked files, index, refs, configuration and markers leave the snapshot intact" {
  seed_bare_repo "$upstream" "upstream change"
  run splice pull vendor/a --pause-after after-fetch --save-to "$saved"
  [ "$status" -eq 75 ]
  for change in worktree index head config fetched marker branch; do
    head="$(git rev-parse HEAD)"
    fetched="$(git for-each-ref --format='%(refname)' refs/splices/ | head -1)"
    old="$(git rev-parse "$fetched")"
    case "$change" in
      worktree) echo changed >>vendor/a/file.txt ;;
      index) echo changed >>vendor/a/file.txt; git add vendor/a/file.txt ;;
      head) git commit -q --allow-empty -m changed ;;
      config) git config continuation.changed true ;;
      fetched) git update-ref "$fetched" HEAD ;;
      marker) echo changed >.git/SPLICE_PULL_START ;;
      branch) git switch -q -c other ;;
    esac
    run splice pull --continue-from "$saved"
    [ "$status" -eq 1 ]
    [[ "$output" == *"repository state changed"* ]]
    [ -s "$saved" ]
    git reset -q --hard "$head"
    git config --unset continuation.changed || true
    git update-ref "$fetched" "$old"
    rm -f .git/SPLICE_PULL_START
    git switch -q main
  done
}

@test "continuation: prepared push survives garbage collection and publishes its exact commit once" {
  commit_local "$monorepo" vendor/a "local change"
  old="$(git --git-dir="$upstream" rev-parse main)"
  run splice push vendor/a --pause-after after-rebuild --save-to "$saved"
  [ "$status" -eq 75 ]
  [ "$(git --git-dir="$upstream" rev-parse main)" = "$old" ]
  prepared="$(git for-each-ref --format='%(objectname)' refs/splice-continuations/ | head -1)"
  [ -n "$prepared" ]
  git reflog expire --expire=now --all
  git gc --prune=now --quiet
  run splice push --continue-from "$saved" --pause-after after-push
  [ "$status" -eq 75 ]
  [ "$(git --git-dir="$upstream" rev-parse main)" = "$prepared" ]
  run splice push --continue-from "$saved"
  [ "$status" -eq 0 ]
  [[ "$output" != *" pushed "* ]]
  [ -z "$(git for-each-ref refs/splice-continuations/)" ]
  [ ! -e "$saved" ]
}

@test "continuation: wrong command, version, options and malformed files fail without changing state" {
  run splice pull vendor/a --pause-after after-fetch --save-to "$saved"
  [ "$status" -eq 75 ]
  before="$(git rev-parse HEAD)"
  run splice push --continue-from "$saved"
  [ "$status" -eq 1 ]
  run splice pull --continue-from "$saved" --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"retains the original options"* ]]
  sed 's/"format": 1/"format": 99/' "$saved" >"$saved.bad"
  run splice pull --continue-from "$saved.bad"
  [ "$status" -eq 1 ]
  [[ "$output" == *"another command or git-splice version"* ]]
  printf '{' >"$saved.bad"
  run splice pull --continue-from "$saved.bad"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid continuation"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -s "$saved" ]
}

@test "continuation: invalid pause requests and existing files fail before fetching" {
  for options in '--pause-after nowhere' '--pause-after after-merge' '--save-to unused'; do
    read -r -a args <<<"$options"
    run splice pull vendor/a "${args[@]}"
    [ "$status" -eq 1 ]
  done
  echo keep >"$saved"
  run splice pull vendor/a --pause-after after-fetch --save-to "$saved"
  [ "$status" -eq 1 ]
  [ "$(cat "$saved")" = keep ]
}

@test "continuation: recursive rebase resumes folding before replaying the branch's own commits" {
  base="$(git rev-parse HEAD)"
  commit_local "$monorepo" vendor/a "local notes" notes.txt
  tip="$(git rev-parse HEAD)"
  seed_bare_repo "$upstream" "upstream change" main other.txt
  run splice pull --rebase --recursive vendor/a --pause-after before-fold --save-to "$saved"
  [ "$status" -eq 75 ]
  ! git symbolic-ref --quiet HEAD
  [ "$(git rev-parse main)" = "$tip" ]
  run splice pull --continue-from "$saved" --pause-after after-fold
  [ "$status" -eq 75 ]
  ! git symbolic-ref --quiet HEAD
  [ "$(git rev-parse main)" = "$tip" ]
  run splice pull --continue-from "$saved"
  [ "$status" -eq 0 ]
  [ "$(git branch --show-current)" = main ]
  [ "$(git show HEAD:vendor/a/notes.txt)" = "local notes" ]
  [ "$(git show HEAD:vendor/a/other.txt)" = "upstream change" ]
  [ "$(git rev-list --count "$base..HEAD")" -eq 2 ]
  ! git rev-parse --verify --quiet SPLICE_PULL_START
  [ ! -e "$saved" ]
}

@test "continuation: hooks must be supplied again and the consumed hook is not repeated" {
  seed_bare_repo "$upstream" "upstream change"
  run splice pull vendor/a --exec 'echo "$GIT_SPLICE_EVENT" >>../events' --pause-after after-fetch --save-to "$saved"
  [ "$status" -eq 75 ]
  [ "$(cat ../events)" = after-fetch ]
  run splice pull --continue-from "$saved" --exec 'echo "$GIT_SPLICE_EVENT" >>../events'
  [ "$status" -eq 0 ]
  [ "$(cat ../events)" = $'after-fetch\nafter-merge' ]
}

@test "continuation: a consumer saves stdin and interrupts pull with its own exit code" {
  seed_bare_repo "$upstream" "upstream change"
  before="$(git rev-parse HEAD)"
  export CONTINUATION_FILE="$saved"
  run splice pull vendor/a --exec 'cat >"$CONTINUATION_FILE"; exit 23'
  [ "$status" -eq 23 ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -s "$saved" ]
  run splice pull --continue-from "$saved" --exec 'echo "$GIT_SPLICE_EVENT"'
  [ "$status" -eq 0 ]
  [[ "$output" != *after-fetch* ]]
  [[ "$output" == *after-merge* ]]
  [[ "$output" != *" fetched"* ]]
  [ "$(git show HEAD:vendor/a/file.txt | tail -1)" = "upstream change" ]
}

@test "continuation: a consumer stops before and after publication without publishing twice" {
  commit_local "$monorepo" vendor/a "local change"
  export CONTINUATION_FILE="$saved"
  old="$(git --git-dir="$upstream" rev-parse main)"
  run splice push vendor/a --exec 'cat >"$CONTINUATION_FILE"; exit 17'
  [ "$status" -eq 17 ]
  [ "$(git --git-dir="$upstream" rev-parse main)" = "$old" ]
  prepared="$(git for-each-ref --format='%(objectname)' refs/splice-continuations/ | head -1)"
  [ -n "$prepared" ]
  git reflog expire --expire=now --all
  git gc --prune=now --quiet
  run splice push --continue-from "$saved" --exec 'cat >"$CONTINUATION_FILE"; exit 19'
  [ "$status" -eq 19 ]
  [ "$(git --git-dir="$upstream" rev-parse main)" = "$prepared" ]
  run splice push --continue-from "$saved"
  [ "$status" -eq 0 ]
  [[ "$output" != *" pushed "* ]]
  [ -z "$(git for-each-ref refs/splice-continuations/)" ]
}

@test "continuation: successful consumers may ignore large stdin payloads without blocking or retaining refs" {
  padding="$(printf '%10000s' x)"
  for i in {1..10}; do
    git config "payload.padding$i" "$padding"
  done
  commit_local "$monorepo" vendor/a "local change"
  run splice push vendor/a --exec 'exit 0'
  [ "$status" -eq 0 ]
  [ -z "$(git for-each-ref refs/splice-continuations/)" ]
}
