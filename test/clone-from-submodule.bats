setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  # Commits inside the submodule's checkout need an identity too.
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
}

# Commits a submodule of $upstream at vendor/a, checked out, at upstream's
# main.
add_submodule() {
  git -c protocol.file.allow=always submodule add -q "$upstream" vendor/a
  git commit -q -m "add vendor/a as a submodule"
}

@test "clone --from-submodule: one commit replaces the submodule with its files and a .splice" {
  add_submodule
  local before pinned
  before="$(git rev-parse HEAD)"
  pinned="$(git rev-parse HEAD:vendor/a)"
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a: cloned ${pinned:0:7} from the submodule"* ]]
  [ "$(git rev-parse HEAD^)" = "$before" ]
  [ "$(git log -1 --format=%s)" = "splice: clone vendor/a from submodule at ${pinned:0:7}" ]
  [ "$(path_mode HEAD vendor/a)" = 040000 ]
  [ "$(cat vendor/a/file.txt)" = seed ]
  [ ! -e vendor/a/.git ]
  [ "$(splice_config vendor/a commit)" = "$pinned" ]
  [ "$(git config --file vendor/a/.splice upstream.origin.url)" = "$upstream" ]
  [[ "$(splice_config vendor/a id)" =~ ^[0-9a-f]{16}$ ]]
  [ -z "$(git status --porcelain)" ]
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = up-to-date ]
}

@test "clone --from-submodule: removes .gitmodules once empty, and the submodule's config" {
  add_submodule
  cmd_clone --from-submodule vendor/a
  ! git cat-file -e HEAD:.gitmodules
  [ ! -e .gitmodules ]
  [ -z "$(git config --get-regexp '^submodule\.' || true)" ]
}

@test "clone --from-submodule: keeps the other submodules in .gitmodules" {
  add_submodule
  git -c protocol.file.allow=always submodule add -q "$upstream" vendor/b
  git commit -q -m "add vendor/b as a submodule"
  cmd_clone --from-submodule vendor/a
  [ "$(git config --file .gitmodules --get-regexp '\.path$')" = "submodule.vendor/b.path vendor/b" ]
  [ "$(path_mode HEAD vendor/b)" = 160000 ]
}

@test "clone --from-submodule: keeps the submodule's commit, not upstream's newest" {
  add_submodule
  local pinned
  pinned="$(git rev-parse HEAD:vendor/a)"
  seed_bare_repo "$upstream" "newer"
  cmd_clone --from-submodule vendor/a
  [ "$(splice_config vendor/a commit)" = "$pinned" ]
  [ "$(cat vendor/a/file.txt)" = seed ]
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = pull ]
}

@test "clone --from-submodule: a submodule that was never checked out gets its files" {
  add_submodule
  git clone -q "$monorepo" "$BATS_TEST_TMPDIR/colleague"
  cd "$BATS_TEST_TMPDIR/colleague"
  [ -z "$(ls -A vendor/a)" ]
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/file.txt)" = seed ]
  [ -z "$(git status --porcelain)" ]
  [[ "$output" != *"repository stays"* ]]
}

@test "clone --from-submodule: files the checkout ignores stay, and so does its repository" {
  add_submodule
  echo "build/" >"$BATS_TEST_TMPDIR/exclude"
  git -C vendor/a config core.excludesFile "$BATS_TEST_TMPDIR/exclude"
  mkdir vendor/a/build && echo "output" >vendor/a/build/out.txt
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/build/out.txt)" = output ]
  [ -d .git/modules/vendor/a ]
  [[ "$output" == *"vendor/a: the submodule's repository stays in $monorepo/.git/modules/vendor/a"* ]]
}

@test "clone --from-submodule: a checkout with its own .git moves it to .git/modules first" {
  git clone -q "$upstream" vendor/a
  git -C vendor/a branch local-work
  git submodule add -q "$upstream" vendor/a
  git commit -q -m "add vendor/a as a submodule"
  [ -d vendor/a/.git ]
  cmd_clone --from-submodule vendor/a
  [ ! -e vendor/a/.git ]
  git --git-dir=.git/modules/vendor/a rev-parse --verify --quiet local-work
}

@test "clone --from-submodule: warns about settings a splice has no equivalent for" {
  add_submodule
  git config --file .gitmodules submodule.vendor/a.branch release
  git config --file .gitmodules submodule.vendor/a.shallow true
  git commit -q -a -m "follow release"
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: dropping submodule.vendor/a.branch from .gitmodules"* ]]
  [[ "$output" == *"vendor/a: dropping submodule.vendor/a.shallow from .gitmodules"* ]]
}

@test "clone --from-submodule: refuses a commit no upstream branch has" {
  add_submodule
  echo "local" >>vendor/a/file.txt
  git -C vendor/a commit -q -a -m "unpushed"
  git add vendor/a && git commit -q -m "bump vendor/a"
  local before
  before="$(git rev-parse HEAD)"
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: no upstream branch has the submodule's commit"*"push it there first"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -e vendor/a/.git ]
}

@test "clone --from-submodule: refuses a checkout with changes, or at another commit" {
  add_submodule
  echo "edit" >>vendor/a/file.txt
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: the submodule's checkout has changes"* ]]

  git -C vendor/a checkout -q -- file.txt
  echo "new" >vendor/a/untracked.txt
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: the submodule's checkout has changes"* ]]

  rm vendor/a/untracked.txt
  git -C vendor/a commit -q --allow-empty -m "moved on"
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: the submodule's checkout isn't at"* ]]
  [ "$(path_mode HEAD vendor/a)" = 160000 ]
}

@test "clone --from-submodule: an edit status doesn't show, behind assume-unchanged, is kept" {
  add_submodule
  git -C vendor/a update-index --assume-unchanged file.txt
  echo "local tuning" >vendor/a/file.txt
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/file.txt)" = "local tuning" ]
  [ "$(git show HEAD:vendor/a/file.txt)" = seed ]
  [ "$(git status --porcelain)" = " M vendor/a/file.txt" ]
}

@test "clone --from-submodule: a deletion behind assume-unchanged comes back, as the help says" {
  add_submodule
  git -C vendor/a update-index --assume-unchanged file.txt
  rm vendor/a/file.txt
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/file.txt)" = seed ]
}

@test "clone --from-submodule: refuses an ignored .splice in the checkout" {
  add_submodule
  echo ".splice" >"$BATS_TEST_TMPDIR/exclude"
  git -C vendor/a config core.excludesFile "$BATS_TEST_TMPDIR/exclude"
  echo "mine" >vendor/a/.splice
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/.splice exists in the submodule's checkout -- move it away first"* ]]
  [ "$(cat vendor/a/.splice)" = mine ]
  [ "$(path_mode HEAD vendor/a)" = 160000 ]
}

@test "clone --from-submodule: refuses staged changes and uncommitted .gitmodules edits" {
  add_submodule
  echo "app" >app.txt && git add app.txt
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"there are staged changes"* ]]

  git rm -q --cached app.txt
  git config --file .gitmodules submodule.vendor/a.branch release
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *".gitmodules has uncommitted changes"* ]]
}

@test "clone --from-submodule: refuses a submodule with submodules of its own" {
  local inner="$BATS_TEST_TMPDIR/inner.git"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "inner"
  add_upstream_submodule "$upstream" "$inner" libs/inner
  add_submodule
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: the submodule has a submodule of its own, libs/inner -- turn it into a splice in its upstream first"* ]]
}

@test "clone --from-submodule: refuses a path that is no submodule, and --merge" {
  mkdir -p vendor/b && echo x >vendor/b/x.txt && git add vendor && git commit -q -m b
  run cmd_clone --from-submodule vendor/b
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/b: no submodule committed here"* ]]

  add_submodule
  run cmd_clone --merge --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"--from-submodule takes no --merge"* ]]
}

@test "clone: names --from-submodule for a path that is a submodule" {
  add_submodule
  run cmd_clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a is a submodule -- 'git splice clone --from-submodule vendor/a' turns it into a splice"* ]]
}

@test "clone --from-submodule: records upstream's default branch when it's named differently" {
  local other="$BATS_TEST_TMPDIR/other.git"
  make_bare_repo "$other" master
  seed_bare_repo "$other" "seed" master
  git -c protocol.file.allow=always submodule add -q "$other" vendor/a
  git commit -q -m "add vendor/a as a submodule"
  cmd_clone --from-submodule vendor/a
  [ "$(upstream_config vendor/a origin default-branch)" = master ]
}

@test "resolve_submodule_url: relative URLs, as git submodule reads them" {
  git remote add origin https://git.example.com/org/mono.git
  [ "$(resolve_submodule_url https://other.example.com/lib.git)" = https://other.example.com/lib.git ]
  [ "$(resolve_submodule_url ../lib.git)" = https://git.example.com/org/lib.git ]
  [ "$(resolve_submodule_url ./lib.git)" = https://git.example.com/org/mono.git/lib.git ]
  [ "$(resolve_submodule_url ../../other/lib.git)" = https://git.example.com/other/lib.git ]
  git remote set-url origin git@git.example.com:org/mono.git
  [ "$(resolve_submodule_url ../lib.git)" = git@git.example.com:org/lib.git ]
  git remote set-url origin host:mono.git
  [ "$(resolve_submodule_url ../lib.git)" = host:lib.git ]
}

@test "resolve_submodule_url: a remote URL that is a relative path is relative to the monorepo" {
  git remote add origin mono.git
  [ "$(resolve_submodule_url ../lib.git)" = "$monorepo/lib.git" ]
  git remote set-url origin ../mono.git
  [ "$(resolve_submodule_url ../lib.git)" = "$monorepo/../lib.git" ]
}

@test "resolve_submodule_url: the current branch's remote first, the monorepo itself without one" {
  [ "$(resolve_submodule_url ../lib.git)" = "$BATS_TEST_TMPDIR/lib.git" ]
  git remote add origin https://git.example.com/org/mono.git
  git remote add fork https://git.example.com/me/mono.git
  git config branch.main.remote fork
  [ "$(resolve_submodule_url ../lib.git)" = https://git.example.com/me/lib.git ]
}

@test "clone --from-submodule: resolves a relative URL and records it absolute" {
  git remote add origin "$BATS_TEST_TMPDIR/mono.git"
  git -c protocol.file.allow=always submodule add -q ../upstream.git vendor/a
  git commit -q -m "add vendor/a as a submodule"
  cmd_clone --from-submodule vendor/a
  [ "$(git config --file vendor/a/.splice upstream.origin.url)" = "$BATS_TEST_TMPDIR/upstream.git" ]
}

@test "clone --from-submodule: a branch that still has the submodule merges the conversion cleanly" {
  add_submodule
  git checkout -q -b feature
  echo "app" >app.txt && git add app.txt && git commit -q -m "app"
  git checkout -q main
  cmd_clone --from-submodule vendor/a
  git checkout -q feature
  git merge -q --no-edit main
  [ "$(path_mode HEAD vendor/a)" = 040000 ]
  [ "$(cat vendor/a/file.txt)" = seed ]
  [ "$(cat app.txt)" = app ]
  [ -z "$(git status --porcelain)" ]
}

@test "clone --from-submodule: finds the settings of a submodule whose name isn't its path" {
  git -c protocol.file.allow=always submodule add -q --name 'lib+x(1).v2' "$upstream" vendor/a
  git config --file .gitmodules 'submodule.lib+x(1).v2.branch' release
  git commit -q -a -m "add vendor/a as a submodule"
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"dropping submodule.lib+x(1).v2.branch from .gitmodules"* ]]
  [[ "$output" != *"dropping submodule.lib+x(1).v2.url"* ]]
  [ ! -e .gitmodules ]
}

@test "clone --from-submodule: refuses a .gitmodules edit status doesn't show, behind assume-unchanged" {
  add_submodule
  git update-index --assume-unchanged .gitmodules
  echo "# my notes" >>.gitmodules
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: .gitmodules has uncommitted changes"* ]]
  [ "$(tail -1 .gitmodules)" = "# my notes" ]
  [ "$(path_mode HEAD vendor/a)" = 160000 ]
}

@test "clone --from-submodule: refuses a .gitmodules deleted but not committed, when other submodules stay in it" {
  add_submodule
  git -c protocol.file.allow=always submodule add -q "$upstream" vendor/b
  git commit -q -m "add vendor/b as a submodule"
  rm .gitmodules
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: .gitmodules has uncommitted changes"* ]]
  [ ! -e .gitmodules ]
  [ "$(path_mode HEAD vendor/a)" = 160000 ]
}

@test "clone --from-submodule: refuses a file or symbolic link in place of an uninitialized submodule, before fetching" {
  add_submodule
  git clone -q "$monorepo" "$BATS_TEST_TMPDIR/colleague"
  cd "$BATS_TEST_TMPDIR/colleague"
  rmdir vendor/a && echo "notes" >vendor/a
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: a file takes the place of the uninitialized submodule"* ]]
  [ "$(cat vendor/a)" = notes ]

  rm vendor/a && mkdir empty && ln -s ../empty vendor/a
  run cmd_clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: a symbolic link takes the submodule's place"* ]]
  [ -L vendor/a ]
  [ -z "$(git for-each-ref refs/splices/)" ]
  git diff --cached --quiet
}
