setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  local scenario
  for scenario in \
    01-everyday-sync/02-up-to-date \
    02-starting-a-splice/01-clone-copied-content \
    02-starting-a-splice/02-clone-differing-content \
    02-starting-a-splice/03-clone-on-feature-branch \
    02-starting-a-splice/06-clone-without-commits \
    02-starting-a-splice/09-clone-under-monorepo-attributes; do
    load "scenarios/$scenario/setup"
  done
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

new_upstream() {
  make_bare_repo "$upstream" "${1:-main}"
  seed_bare_repo "$upstream" "seed" "${1:-main}"
  init_monorepo "$monorepo"
  cd "$monorepo"
}

@test "clone: splices upstream in as one commit with a .splice" {
  new_upstream
  local before
  before="$(git rev-parse HEAD)"
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD^)" = "$before" ]
  [ "$(cat vendor/a/file.txt)" = seed ]
  [ "$(git config --file vendor/a/.splice upstream.origin.url)" = "$upstream" ]
  [ "$(splice_config vendor/a commit)" = "$(git -C "$upstream" rev-parse main)" ]
  [ -z "$(upstream_config vendor/a origin default-branch)" ]
  [ -z "$(git remote)" ]
  [ -z "$(git status --porcelain)" ]
  [ "$(splice_state vendor/a)" = up-to-date ]
}

@test "clone -m: the commit gets the message, and .splice still records the commit" {
  new_upstream
  run splice clone -m "a: add the parser" "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "a: add the parser" ]
  [ "$(splice_config vendor/a commit)" = "$(git -C "$upstream" rev-parse main)" ]
}

@test "clone --merge -m: on a conflict, git commit keeps the message" {
  new_upstream
  mkdir -p vendor/a
  echo local >vendor/a/file.txt
  git add vendor/a
  git commit -q -m "local copy"
  run splice clone --merge -m "b: splice the copy in" "$upstream" vendor/a
  [ "$status" -eq 1 ]
  echo merged >vendor/a/file.txt
  git add vendor/a/file.txt
  git commit -q --no-edit
  [ "$(git log -1 --format=%s)" = "b: splice the copy in" ]
}

@test "clone: gives the splice an id, another one than a clone at another path" {
  new_upstream
  splice clone "$upstream" vendor/a
  splice clone "$upstream" vendor/b
  [[ "$(splice_config vendor/a id)" =~ ^[0-9a-f]{16}$ ]]
  [ "$(splice_config vendor/a id)" != "$(splice_config vendor/b id)" ]
}

@test "clone: at the same path on the same commit, another upstream gets another id" {
  new_upstream
  local other="$BATS_TEST_TMPDIR/other.git"
  make_bare_repo "$other"
  seed_bare_repo "$other" "other seed"
  git checkout -q -b one
  splice clone "$upstream" vendor/a
  git checkout -q -b other main
  splice clone "$other" vendor/a
  [ "$(splice_config vendor/a id)" != "$(splice_config vendor/a id one)" ]
}

@test "clone: names the folder after the repository by default" {
  new_upstream
  splice clone "$upstream"
  [ -f upstream/.splice ]
}

@test "clone: records upstream's default branch when it's named differently" {
  new_upstream master
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [ "$(upstream_config vendor/a origin default-branch)" = master ]
  [[ "$output" == *"cloned"*"from master"* ]]
}

@test "clone: on a branch upstream lacks, uses upstream's default branch" {
  scenario_clone_on_feature_branch "$monorepo" "$upstream"
  cd "$monorepo"
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"upstream has no 'feature' branch -- using 'main'"* ]]
  [ "$(splice_state vendor/a)" = missing-branch ]
}

@test "clone: a folder with exactly upstream's content only gets a .splice" {
  scenario_clone_copied_content "$monorepo" "$upstream"
  cd "$monorepo"
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git show --name-only --format= HEAD)" = "vendor/a/.splice" ]
}

@test "clone: refuses a folder that differs from upstream" {
  scenario_clone_differing_content "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a exists and differs"*"'--merge' keeps both"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "clone --merge: every differing file is a conflict, nothing is lost" {
  scenario_clone_differing_content "$monorepo" "$upstream"
  cd "$monorepo"
  run splice clone --merge "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT (add/add)"*"vendor/a/file.txt"* ]]
  [ "$(cat vendor/a/local.txt)" = "only local" ]
  [ "$(cat vendor/a/upstream.txt)" = "only upstream" ]
  [ "$(git status --porcelain vendor/a/file.txt)" = "AA vendor/a/file.txt" ]
  echo resolved >vendor/a/file.txt
  git add vendor/a/file.txt
  git commit -q --no-edit
  [ "$(git rev-list --parents -1 HEAD | wc -w)" -eq 2 ]
  [ "$(splice_state vendor/a)" = push ]
}

@test "clone: refuses an existing splice and an empty upstream" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice clone "$upstream" vendor/a
  [[ "$output" == *"vendor/a is a splice already"* ]]
  make_bare_repo "$BATS_TEST_TMPDIR/empty.git"
  run splice clone "$BATS_TEST_TMPDIR/empty.git" vendor/b
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no branches yet -- to publish vendor/b there, use 'git splice init"* ]]
}

@test "clone: refuses a monorepo without commits up front" {
  scenario_clone_without_commits "$monorepo" "$upstream"
  cd "$monorepo"
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no commits yet"* ]]
}

@test "clone: refuses a path that can't be part of a ref, before fetching" {
  scenario_clone_without_commits "$monorepo" "$upstream"
  cd "$monorepo"
  git commit -q --allow-empty -m "initial commit"
  run splice clone "$upstream" "my lib"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'my lib' isn't supported as a splice path yet"* ]]
  [ -z "$(git for-each-ref refs/splices/)" ]
}

@test "clone: refuses an upstream with a .splice at its root" {
  new_upstream
  seed_bare_repo "$upstream" "[splice]" main .splice
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"upstream has a .splice at its root, which would replace vendor/a/.splice"* ]]
  [ -z "$(git ls-files vendor/a)" ]
}

@test "clone: refuses an upstream with a submodule, which nobody could check out" {
  new_upstream
  local inner="$BATS_TEST_TMPDIR/inner.git"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "inner"
  add_upstream_submodule "$upstream" "$inner" libs/inner
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: upstream has a submodule, libs/inner, which nobody could check out in the monorepo -- turn it into a splice in the upstream first"* ]]
  [ -z "$(git ls-files vendor/a)" ]
}

@test "clone: an upstream file whose name only resembles .splice is content" {
  new_upstream
  seed_bare_repo "$upstream" "x" main xsplice
  seed_bare_repo "$upstream" "x" main docs/-splice
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/xsplice)" = x ]
}

@test "clone: an upstream with only an empty commit works with every command" {
  make_bare_repo "$upstream"
  local tmp="$BATS_TEST_TMPDIR/seed"
  git clone -q "$upstream" "$tmp" 2>/dev/null
  git -C "$tmp" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m init
  git -C "$tmp" push -q origin HEAD:main
  init_monorepo "$monorepo"
  cd "$monorepo"
  splice clone "$upstream" vendor/a
  local cmd
  for cmd in status diff log "push vendor/a" "merge vendor/a"; do
    # shellcheck disable=SC2086
    run splice $cmd
    [ "$status" -eq 0 ]
  done
  run splice status
  [ "${lines[*]:1}" = "  up to date  vendor/a" ]
}

@test "clone: refuses a path that is a file" {
  new_upstream
  echo x >vendor
  git add vendor && git commit -q -m "a file"
  run splice clone "$upstream" vendor
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor is a file, not a folder"* ]]
  ! git rev-parse --quiet --verify CHERRY_PICK_HEAD
}

@test "clone: asks for the monorepo's default branch when upstream's is named differently" {
  new_upstream master
  git config --unset init.defaultBranch
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"upstream's default branch is 'master', and the monorepo's can't be determined"* ]]
  git config init.defaultBranch main
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
}

@test "clone: refuses where the monorepo's attributes would apply to upstream's files, naming the line; with it committed, clones the files as upstream committed them" {
  scenario_clone_under_monorepo_attributes "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: attributes in .gitattributes or above it would change how Git checks out or stores some of its files, unlike in upstream -- add 'vendor/a/** !text !eol !filter !ident !working-tree-encoding' to .gitattributes, commit it, and run clone again"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ ! -e vendor/a ]
  echo 'vendor/a/** !text !eol !filter !ident !working-tree-encoding' >>.gitattributes
  git commit -q -a -m "keep the monorepo's line endings off vendor/a"
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [ -z "$(git status --porcelain)" ]
  [ "$(od -c vendor/a/run.bat)" = "$(printf 'echo run\n' | od -c)" ]
}

@test "clone: the line it names skips a .gitattributes that's a symbolic link, which Git doesn't read" {
  scenario_clone_under_monorepo_attributes "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir vendor
  echo "notes" >notes.txt
  ln -s ../notes.txt vendor/.gitattributes
  git add notes.txt vendor/.gitattributes
  git commit -q -m "notes, and a link to them"
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"add 'vendor/a/** !text !eol !filter !ident !working-tree-encoding' to .gitattributes,"* ]]
}

@test "clone: refuses without naming a line where unsetting the monorepo's attributes can't make them upstream's" {
  new_upstream
  commit_raw_file "$upstream" .gitattributes '[attr]crlf-text text eol=crlf\n*.bat crlf-text\n'
  commit_raw_file "$upstream" run.bat 'echo run\n'
  printf '*.png binary\n' >.gitattributes
  git add .gitattributes
  git commit -q -m "binary images"
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: Git would check out or store some of its files otherwise than in upstream, and unsetting attributes above it can't change that"* ]]
}
