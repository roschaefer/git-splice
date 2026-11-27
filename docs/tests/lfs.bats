setup() {
  load 'helpers/fixtures'
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/.gitconfig" GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_VALUE_0=https://git.example.com/monorepo.git
  export GIT_CONFIG_KEY_0="url.file://$BATS_TEST_TMPDIR/monorepo.git.insteadOf"
  git lfs install --skip-repo >/dev/null
  # Commits in a fresh clone of the monorepo need an identity too.
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
  load '../09-scenarios/04-upstreams/08-lfs-upstream/01-cloned/01-retrained-upstream/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream"
}

# The path of the content with SHA-256 <oid> in the LFS store <lfs>.
lfs_object() {
  printf '%s/objects/%s/%s/%s\n' "$1" "${2:0:2}" "${2:2:2}" "$2"
}

# The SHA-256 of the content file <file> points to in <rev>.
lfs_oid() {
  git show "$1:$2" | sed -n 's/^oid sha256://p'
}

@test "fetch: downloads the Git LFS content of the branch a merge would take" {
  scenario_retrained_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  run splice fetch vendor/a
  [ "$status" -eq 0 ]
  local oid
  oid="$(lfs_oid "$(upstream_refs "file://$upstream")main" model.bin)"
  [ -f "$(lfs_object .git/lfs "$oid")" ]
}

@test "fetch: lfs.fetchrecentalways doesn't ask the upstream for the monorepo's content" {
  scenario_retrained_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  echo "weights, edited here" >vendor/a/model.bin
  git commit -qam "edit the model here"
  local oid
  oid="$(lfs_oid HEAD vendor/a/model.bin)"
  rm "$(lfs_object .git/lfs "$oid")"
  git config lfs.fetchrecentalways true
  GIT_TRACE="$BATS_TEST_TMPDIR/trace" run splice fetch vendor/a
  [ "$status" -eq 0 ]
  grep -q "git-lfs" "$BATS_TEST_TMPDIR/trace"
  ! grep -q "$oid" "$BATS_TEST_TMPDIR/trace"
}

@test "fetch: downloads only from the upstream the splice uses" {
  scenario_retrained_upstream "$monorepo" "$upstream"
  git clone -q --bare "file://$upstream" "$BATS_TEST_TMPDIR/fork.git"
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.fork.url "file://$BATS_TEST_TMPDIR/fork.git"
  git commit -q -m "vendor/a: add a fork without Git LFS content" -- vendor/a/.splice
  run splice fetch vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a fetched from fork"* ]]
}

@test "clone: downloads the Git LFS content of an upstream given as a path" {
  scenario_lfs_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  run splice clone "$(realpath --relative-to=. "$upstream")" vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/model.bin)" = "weights, version 1" ]
}

@test "fetch: an upstream without Git LFS files runs no git lfs" {
  load '../09-scenarios/01-everyday-sync/02-up-to-date/setup'
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  cd "$monorepo"
  stub_git 'if [ "$1" = lfs ]; then echo "ran git lfs" >&2; exit 1; fi'
  run splice fetch vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" != *"ran git lfs"* ]]
}

@test "pull: a failed Git LFS download stops before the merge" {
  scenario_retrained_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  local oid before
  oid="$(git -C "$upstream" show main:model.bin | sed -n 's/^oid sha256://p')"
  rm "$(lfs_object "$upstream/lfs" "$oid")"
  before="$(git rev-parse HEAD)"
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a fetch failed"* ]]
  [[ "$output" != *"pulled"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -z "$(git status --porcelain)" ]
}

@test "pull: GIT_LFS_SKIP_SMUDGE downloads no Git LFS content" {
  scenario_retrained_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  GIT_LFS_SKIP_SMUDGE=1 run splice pull vendor/a
  [ "$status" -eq 0 ]
  local oid
  oid="$(lfs_oid HEAD vendor/a/model.bin)"
  [ ! -e "$(lfs_object .git/lfs "$oid")" ]
}

@test "clone: says when an upstream stores files in Git LFS and it isn't installed" {
  scenario_lfs_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  local bin="$BATS_TEST_TMPDIR/no-lfs"
  mkdir "$bin"
  ln -s "$(command -v git)" "$bin/git"
  PATH="$bin" run "$ENTRYPOINT" clone "file://$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *" stores files in Git LFS, which isn't installed here"* ]]
  [[ "$output" == *"vendor/a: Git LFS download failed"* ]]
  [ ! -e vendor/a ]
}

@test "clone: without Git LFS set up, says so and checks out pointers" {
  scenario_lfs_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  local bin="$BATS_TEST_TMPDIR/no-lfs"
  mkdir "$bin"
  ln -s "$(command -v git)" "$bin/git"
  GIT_CONFIG_GLOBAL=/dev/null PATH="$bin" run "$ENTRYPOINT" clone "file://$upstream" vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"??   vendor/a: "*" stores files in Git LFS, and checkouts here keep them as pointers"* ]]
  [[ "$(cat vendor/a/model.bin)" == "version https://git-lfs.github.com/spec/v1"* ]]
}

@test "pull: Git LFS set up with --skip-smudge downloads no Git LFS content" {
  scenario_retrained_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  git lfs install --skip-repo --skip-smudge >/dev/null
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"??   vendor/a: "*" stores files in Git LFS, and checkouts here keep them as pointers"* ]]
  local oid
  oid="$(lfs_oid HEAD vendor/a/model.bin)"
  [ ! -e "$(lfs_object .git/lfs "$oid")" ]
}

@test "merge: refuses before the checkout when the Git LFS content isn't here" {
  scenario_retrained_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  GIT_LFS_SKIP_SMUDGE=1 splice fetch vendor/a
  local before
  before="$(git rev-parse HEAD)"
  run splice merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: the Git LFS content of vendor/a/model.bin in "*" isn't here -- 'git splice fetch vendor/a' downloads it"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -z "$(git status --porcelain)" ]
  splice fetch vendor/a
  run splice merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/model.bin)" = "weights, version 2" ]
}

@test "merge --rebase: refuses before the rebase when the Git LFS content isn't here" {
  scenario_retrained_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  echo local >vendor/a/local.txt
  git add vendor/a/local.txt
  git commit -q -m "a local change"
  GIT_LFS_SKIP_SMUDGE=1 splice fetch vendor/a
  local before
  before="$(git rev-parse HEAD)"
  run splice merge --rebase vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"isn't here -- 'git splice fetch vendor/a' downloads it"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -z "$(git status --porcelain)" ]
}

@test "clone --from-submodule: downloads the Git LFS content of a submodule that was never checked out" {
  scenario_lfs_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  git -c protocol.file.allow=always submodule add -q "file://$upstream" vendor/a
  git commit -q -m "add vendor/a as a submodule"
  git push -q origin main
  git clone -q https://git.example.com/monorepo.git "$BATS_TEST_TMPDIR/fresh"
  cd "$BATS_TEST_TMPDIR/fresh"
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/model.bin)" = "weights, version 1" ]
  git push -q origin main
}
