setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load '../09-scenarios/05-nested-splices/01-nested-splices/02-three-levels/setup'
  load '../09-scenarios/04-upstreams/08-lfs-upstream/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  upstream_b="$BATS_TEST_TMPDIR/upstream-b.git"
  upstream_c="$BATS_TEST_TMPDIR/upstream-c.git"
  payload="$BATS_TEST_TMPDIR/checkpoint.json"
}

pull_checkpoint() {
  local result=0
  splice pull "$@" >"$payload.next" || result=$?
  if [[ -s "$payload.next" ]]; then mv "$payload.next" "$payload"; fi
  return "$result"
}

continue_checkpoint() {
  pull_checkpoint --continue-from "$payload" --exec 'cat; exit 1'
}

@test "checkpoints: emitted payload steps through a recursive pull without replaying fetches or merges" {
  scenario_three_levels "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" "b update"
  seed_bare_repo "$upstream_c" "c update"
  cd "$monorepo"
  local start b c
  start="$(git rev-parse HEAD)"
  b="$(git -C "$upstream_b" rev-parse main)"
  c="$(git -C "$upstream_c" rev-parse main)"
  run pull_checkpoint --recursive --exec 'cat; exit 1' vendor/a
  [ "$status" -eq 1 ]
  [ "$(jq -r .event.checkpoint "$payload")" = after-fetch ]
  [ "$(git rev-parse HEAD)" = "$start" ]
  jq -e '.version == 1 and .sequence == 1 and (.event.fetched | length == 3)' "$payload"

  # A continuation uses the commits already fetched, even if the remote moves.
  seed_bare_repo "$upstream_c" "c later"
  run continue_checkpoint
  [ "$status" -eq 1 ]
  [ "$(jq -r .event.path "$payload")" = vendor/a/b ]
  [ "$(splice_config vendor/a/b commit)" = "$b" ]
  [ "$(git rev-list --count "$start..HEAD")" = 1 ]
  local first_merge
  first_merge="$(git rev-parse HEAD)"
  run continue_checkpoint
  [ "$status" -eq 1 ]
  [ "$(jq -r .event.path "$payload")" = vendor/a/b/c ]
  [ "$(splice_config vendor/a/b/c commit)" = "$c" ]
  [ "$(git rev-parse HEAD^1)" = "$first_merge" ]
  run continue_checkpoint
  [ "$status" -eq 1 ]
  [ "$(jq -r .event.checkpoint "$payload")" = before-fold ]
  [ "$(git rev-list --count "$start..HEAD")" = 2 ]
  run continue_checkpoint
  [ "$status" -eq 1 ]
  [ "$(jq -r .event.checkpoint "$payload")" = after-fold ]
  [ "$(git rev-list --count "$start..HEAD")" = 1 ]
  ! git rev-parse --verify --quiet SPLICE_PULL_START
  run continue_checkpoint
  [ "$status" -eq 0 ]
}

@test "checkpoints: a no-op fetch still advances and stdin can supply continuation" {
  scenario_three_levels "$monorepo" "$upstream"
  cd "$monorepo"
  run pull_checkpoint --recursive --exec 'cat; exit 1' vendor/a
  [ "$status" -eq 1 ]
  local head
  head="$(git rev-parse HEAD)"
  run bash -c '"$1" pull --continue-from - --exec "cat; exit 1" <"$2" >"$2.next"' _ "$ENTRYPOINT" "$payload"
  [ "$status" -eq 1 ]
  [ "$(jq -r .event.checkpoint "$payload.next")" = before-fold ]
  [ "$(git rev-parse HEAD)" = "$head" ]
}

@test "checkpoints: script can ignore stdin and a successful script preserves pull behaviour" {
  scenario_three_levels "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" "b update"
  seed_bare_repo "$upstream_c" "c update"
  cd "$monorepo"
  run pull_checkpoint --recursive --exec true vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = 'splice: pull vendor/a and the splices in it' ]
  [ "$(splice_config vendor/a/b/c commit)" = "$(git -C "$upstream_c" rev-parse main)" ]
  [ ! -s "$payload.next" ]
}

@test "checkpoints: discovery fetches a newly introduced splice before its merge" {
  scenario_three_levels "$monorepo" "$upstream"
  local extra="$BATS_TEST_TMPDIR/extra.git" work="$BATS_TEST_TMPDIR/work"
  make_bare_repo "$extra"
  seed_bare_repo "$extra" "extra seed"
  git clone -q "$upstream" "$work"
  git -C "$work" config user.name Test
  git -C "$work" config user.email test@example.com
  (cd "$work" && splice clone "$extra" e && git push -q origin main)
  seed_bare_repo "$extra" "extra update"
  cd "$monorepo"
  run pull_checkpoint --recursive --exec 'cat; exit 1' vendor/a
  [ "$status" -eq 1 ]
  run continue_checkpoint
  [ "$status" -eq 1 ]
  [ "$(jq -r .event.path "$payload")" = vendor/a ]
  run continue_checkpoint
  [ "$status" -eq 1 ]
  [ "$(jq -r .event.checkpoint "$payload")" = after-fetch ]
  [ "$(jq -r '.event.fetched[0].path' "$payload")" = vendor/a/e ]
  [ "$(cat vendor/a/e/file.txt)" = 'extra seed' ]
  run continue_checkpoint
  [ "$status" -eq 1 ]
  [ "$(jq -r .event.path "$payload")" = vendor/a/e ]
  [ "$(cat vendor/a/e/file.txt)" = $'extra seed\nextra update' ]
}

@test "checkpoints: changed nested upstream is fetched and its target survives a pause" {
  scenario_three_levels "$monorepo" "$upstream"
  local replacement="$BATS_TEST_TMPDIR/replacement.git" work="$BATS_TEST_TMPDIR/work"
  git clone -q --bare "$upstream_b" "$replacement"
  seed_bare_repo "$replacement" "replacement update"
  git clone -q "$upstream" "$work"
  git -C "$work" config user.name Test
  git -C "$work" config user.email test@example.com
  git -C "$work" config --file b/.splice upstream.origin.url "$replacement"
  git -C "$work" commit -qam 'move b upstream'
  git -C "$work" push -q origin main
  cd "$monorepo"
  run pull_checkpoint --recursive --exec 'cat; exit 1' vendor/a
  [ "$status" -eq 1 ]
  run continue_checkpoint
  [ "$status" -eq 1 ]
  run continue_checkpoint
  [ "$status" -eq 1 ]
  [ "$(jq -r '.event.fetched[0].url' "$payload")" = "$replacement" ]
  run continue_checkpoint
  [ "$status" -eq 1 ]
  [ "$(jq -r .event.path "$payload")" = vendor/a/b ]
  [ "$(splice_config vendor/a/b commit)" = "$(git -C "$replacement" rev-parse main)" ]
}

@test "checkpoints: make failure leaves its merge applied and permits a repair commit before continuing" {
  scenario_three_levels "$monorepo" "$upstream"
  cd "$monorepo"
  printf 'test:\n\t! grep -q broken vendor/a/b/file.txt\n' >Makefile
  git add Makefile
  git commit -qm 'check the build'
  seed_bare_repo "$upstream_b" broken
  seed_bare_repo "$upstream_c" 'c update'
  export CAPTURE="$payload"
  local build='p=$(cat); printf "%s\n" "$p" >"$CAPTURE"; if [ "$(printf "%s" "$p" | jq -r .event.checkpoint)" = after-merge ]; then make -s; fi'
  run splice pull --recursive --exec "$build" vendor/a
  [ "$status" -eq 1 ]
  [ "$(jq -r .event.path "$payload")" = vendor/a/b ]
  [ "$(splice_config vendor/a/b commit)" = "$(git -C "$upstream_b" rev-parse main)" ]
  [[ "$(cat vendor/a/b/c/file.txt)" != *'c update'* ]]
  sed -i '/broken/d' vendor/a/b/file.txt
  git commit -qam 'repair the build'
  run splice pull --continue-from "$payload" --exec "$build"
  [ "$status" -eq 0 ]
  [[ "$output" == *"isn't a pull"* ]]
  [[ "$(cat vendor/a/b/c/file.txt)" == *'c update'* ]]
}

@test "checkpoints: stale refs, wrong repositories, unknown versions and conflicting options fail before mutation" {
  scenario_three_levels "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" 'b update'
  cd "$monorepo"
  run pull_checkpoint --recursive --exec 'cat; exit 1' vendor/a
  [ "$status" -eq 1 ]
  local head
  head="$(git rev-parse HEAD)"
  jq '.version = 99' "$payload" >"$payload.bad"
  run splice pull --continue-from "$payload.bad" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'unsupported continuation'* ]]
  run splice pull --continue-from "$payload" --exec true --all
  [ "$status" -eq 1 ]
  [[ "$output" == *'only --exec'* ]]
  jq '.repository.root = "/another/repository"' "$payload" >"$payload.bad"
  run splice pull --continue-from "$payload.bad" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'another repository'* ]]
  seed_bare_repo "$upstream_b" 'b newer'
  splice fetch vendor/a/b
  run splice pull --continue-from "$payload" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'fetched refs'* ]]
  [ "$(git rev-parse HEAD)" = "$head" ]
}

@test "checkpoints: an old payload cannot silently replay a completed merge" {
  scenario_three_levels "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" 'b update'
  cd "$monorepo"
  run pull_checkpoint --recursive --exec 'cat; exit 1' vendor/a
  [ "$status" -eq 1 ]
  cp "$payload" "$payload.old"
  run continue_checkpoint
  [ "$status" -eq 1 ]
  run splice pull --continue-from "$payload.old" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'splice configuration changed'* ]]
}

setup_lfs_checkpoint() {
  git lfs version >/dev/null 2>&1 || skip 'Git LFS is not installed'
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  git lfs install --skip-repo >/dev/null
  make_bare_repo "$upstream"
  commit_lfs_file "$upstream" model.bin 'version one' 'add model'
  init_monorepo "$monorepo"
  make_bare_repo "$monorepo.git"
  cd "$monorepo"
  git remote add origin "file://$monorepo.git"
  GIT_LFS_SKIP_SMUDGE=1 splice clone "file://$upstream" vendor/a
  commit_lfs_file "$upstream" model.bin 'version two' 'update model'
  export CHECKPOINT_SCRIPT="$BATS_TEST_DIRNAME/../09-scenarios/04-upstreams/08-lfs-upstream/lfs-fetch.sh"

}

assert_local_lfs_change_reaches_upstream() {
  printf 'version three, trained locally\n' >vendor/a/model.bin
  git add vendor/a/model.bin
  git commit -qm 'train model locally'
  run splice push --exec 'bash "$CHECKPOINT_SCRIPT"' vendor/a
  [ "$status" -eq 0 ]
  git clone -q "file://$upstream" "$BATS_TEST_TMPDIR/upstream-colleague"
  [ "$(cat "$BATS_TEST_TMPDIR/upstream-colleague/model.bin")" = 'version three, trained locally' ]
}

@test "checkpoints: LFS script fetches missing objects from the splice upstream before checkout" {
  setup_lfs_checkpoint
  run splice pull --exec 'bash "$CHECKPOINT_SCRIPT"' vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/model.bin)" = 'version two' ]
  git push -q origin main
  git clone -q "file://$monorepo.git" "$BATS_TEST_TMPDIR/colleague"
  [ "$(cat "$BATS_TEST_TMPDIR/colleague/vendor/a/model.bin")" = 'version two' ]
  assert_local_lfs_change_reaches_upstream
}

@test "checkpoints: scripts run at the repository root and continuation notices configuration or branch changes" {
  scenario_three_levels "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" 'b update'
  cd "$monorepo/vendor"
  export CAPTURE="$payload"
  run splice pull --exec 'pwd >&2; cat >"$CAPTURE"; exit 1' vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"$monorepo"* ]]
  cd "$monorepo"
  git switch -q -c other
  run splice pull --continue-from "$payload" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'another repository, worktree or branch'* ]]
  git switch -q main
  git config branch.main.splice main
  run splice pull --continue-from "$payload" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'Git configuration changed'* ]]
}

@test "checkpoints: a conflict still uses normal resolution and a fresh pull resumes the remaining work" {
  scenario_three_levels "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a/b 'b local'
  seed_bare_repo "$upstream_b" 'b upstream'
  seed_bare_repo "$upstream_c" 'c upstream'
  cd "$monorepo"
  run splice pull --recursive --exec true vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *'Not pulled yet: vendor/a/b/c'* ]]
  echo resolved >vendor/a/b/file.txt
  git add vendor/a/b/file.txt
  git commit -q --no-edit
  run splice pull --recursive --exec true vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a/b/c commit)" = "$(git -C "$upstream_c" rev-parse main)" ]
  ! git rev-parse --verify --quiet SPLICE_PULL_START
}

@test "checkpoints: malformed input, missing script and rebase are refused without changing refs" {
  scenario_three_levels "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git show-ref)"
  printf 'not json\n' >"$payload"
  run splice pull --continue-from "$payload" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'invalid continuation payload'* ]]
  run splice pull --continue-from "$payload"
  [ "$status" -eq 1 ]
  [[ "$output" == *'needs --exec'* ]]
  run splice pull --recursive --rebase --exec true vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *'do not support --rebase yet'* ]]
  [ "$(git show-ref)" = "$before" ]
}


@test "checkpoints: standalone fetch resumes after its script without fetching again or changing HEAD" {
  scenario_three_levels "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" 'b update'
  cd "$monorepo"
  local head fetched
  head="$(git rev-parse HEAD)"
  run bash -c '"$1" fetch --exec "cat; exit 1" vendor/a/b >"$2"' _ "$ENTRYPOINT" "$payload"
  [ "$status" -eq 1 ]
  jq -e '.operation == "fetch" and .event.checkpoint == "after-fetch" and .sequence == 1' "$payload"
  fetched="$(jq -r '.event.fetched[0].new' "$payload")"
  [ "$(git rev-parse HEAD)" = "$head" ]
  seed_bare_repo "$upstream_b" 'b later'
  run splice pull --continue-from "$payload" --exec true
  [ "$status" -eq 1 ]
  [[ "$output" == *'unsupported continuation version or operation'* ]]
  run splice fetch --continue-from "$payload" --exec 'exit 99'
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD)" = "$head" ]
  [ "$(git rev-parse "refs/splices/$(splice key vendor/a/b)/heads/main")" = "$fetched" ]
}

@test "checkpoints: standalone fetch continues tracking after the checkpoint" {
  scenario_three_levels "$monorepo" "$upstream"
  seed_bare_repo "$upstream_b" 'stable update' stable
  cd "$monorepo"
  run bash -c '"$1" fetch --branch stable --track --exec "cat; exit 1" vendor/a/b >"$2"' _ "$ENTRYPOINT" "$payload"
  [ "$status" -eq 1 ]
  ! git config --get-all branch.main.splice
  run splice fetch --continue-from "$payload" --exec true
  [ "$status" -eq 0 ]
  [ "$(git config --get-all branch.main.splice)" = "$(splice key vendor/a/b):stable" ]
  run splice fetch --no-track --exec true vendor/a/b
  [ "$status" -eq 0 ]
  ! git config --get-all branch.main.splice
}

@test "checkpoints: standalone fetch reports failures even when its script succeeds" {
  scenario_three_levels "$monorepo" "$upstream"
  cd "$monorepo"
  mv "$upstream_b" "$upstream_b.offline"
  run splice fetch --exec true vendor/a/b
  [ "$status" -eq 1 ]
  [[ "$output" == *'Failed: vendor/a/b'* ]]
}

@test "checkpoints: fetch can download LFS objects before a separate merge checks them out" {
  setup_lfs_checkpoint
  local head
  head="$(git rev-parse HEAD)"
  run splice fetch --exec 'bash "$CHECKPOINT_SCRIPT"' vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD)" = "$head" ]
  [[ "$(cat vendor/a/model.bin)" == 'version https://git-lfs.github.com/spec/v1'* ]]
  run splice merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/model.bin)" = 'version two' ]
  assert_local_lfs_change_reaches_upstream
}

@test "checkpoints: user-defined reporting ignores fetches and records only applied updates" {
  load '../09-scenarios/01-everyday-sync/05-exec-report/setup'
  scenario_exec_report "$monorepo" "$upstream"
  export REPORT_SCRIPT="$BATS_TEST_DIRNAME/../09-scenarios/01-everyday-sync/05-exec-report/report-updates.sh"
  cd "$monorepo"
  run splice fetch --exec 'sh "$REPORT_SCRIPT"' vendor/a
  [ "$status" -eq 0 ]
  [ ! -s ../updated-splices.txt ]
  run splice pull --exec 'sh "$REPORT_SCRIPT"' vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat ../updated-splices.txt)" = "vendor/a: $(git -C "$upstream" rev-parse --short=7 main)" ]
  run splice pull --exec 'sh "$REPORT_SCRIPT"' vendor/a
  [ "$status" -eq 0 ]
  [ "$(wc -l <../updated-splices.txt)" -eq 1 ]
}


@test "checkpoints: failed LFS download emits continuation and leaves the update unapplied" {
  setup_lfs_checkpoint
  local head
  head="$(git rev-parse HEAD)"
  mv "$upstream/lfs" "$upstream/lfs.offline"
  run pull_checkpoint --exec 'bash "$CHECKPOINT_SCRIPT"' vendor/a
  [ "$status" -eq 1 ]
  jq -e '.operation == "pull" and .event.checkpoint == "after-fetch" and .version == 1' "$payload"
  [ "$(git rev-parse HEAD)" = "$head" ]
  git diff --quiet
  git diff --cached --quiet
  cp -a "$upstream/lfs.offline/." "$upstream/lfs"
  bash "$CHECKPOINT_SCRIPT" <"$payload"
  run splice pull --continue-from "$payload" --exec 'bash "$CHECKPOINT_SCRIPT"'
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/model.bin)" = 'version two' ]
}


@test "checkpoints: each splice pushes its new LFS model to its own upstream after checkpoint downloads" {
  git lfs version >/dev/null 2>&1 || skip 'Git LFS is not installed'
  load '../09-scenarios/04-upstreams/08-lfs-upstream/02-push-to-upstreams/setup'
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$monorepo.git.insteadOf" GIT_CONFIG_VALUE_0=https://git.example.com/monorepo.git
  git lfs install --skip-repo >/dev/null
  scenario_push_to_upstreams "$monorepo" "$upstream"
  export CHECKPOINT_SCRIPT="$BATS_TEST_DIRNAME/../09-scenarios/04-upstreams/08-lfs-upstream/lfs-fetch.sh"
  cd "$monorepo"
  run splice pull --all --exec 'bash "$CHECKPOINT_SCRIPT"'
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/model.bin)" = 'weights, version 2' ]
  [ "$(cat vendor/b/model.bin)" = 'b weights, version 2' ]
  printf 'a weights, trained locally\n' >vendor/a/model.bin
  printf 'b weights, trained locally\n' >vendor/b/model.bin
  git add vendor/a/model.bin vendor/b/model.bin
  git commit -qm 'train both models locally'
  run splice push --all --exec 'bash "$CHECKPOINT_SCRIPT"'
  [ "$status" -eq 0 ]
  git clone -q "file://$upstream" "$BATS_TEST_TMPDIR/a-clone"
  git clone -q "file://$upstream-b.git" "$BATS_TEST_TMPDIR/b-clone"
  [ "$(cat "$BATS_TEST_TMPDIR/a-clone/model.bin")" = 'a weights, trained locally' ]
  [ "$(cat "$BATS_TEST_TMPDIR/b-clone/model.bin")" = 'b weights, trained locally' ]
  [ "$(git -C "$BATS_TEST_TMPDIR/a-clone" ls-tree --name-only HEAD)" = $'.gitattributes\nmodel.bin' ]
  [ "$(git -C "$BATS_TEST_TMPDIR/b-clone" ls-tree --name-only HEAD)" = $'.gitattributes\nmodel.bin' ]
  git push -q origin main
  git clone -q https://git.example.com/monorepo.git "$BATS_TEST_TMPDIR/colleague"
  [ "$(cat "$BATS_TEST_TMPDIR/colleague/vendor/a/model.bin")" = 'a weights, trained locally' ]
  [ "$(cat "$BATS_TEST_TMPDIR/colleague/vendor/b/model.bin")" = 'b weights, trained locally' ]
}
