setup() {
  load 'helpers/fixtures'
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
  run splice clone --from-submodule vendor/a
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
  [ "$(splice_state vendor/a)" = up-to-date ]
}

@test "clone --from-submodule -m: the commit gets the message" {
  add_submodule
  run splice clone --from-submodule -m "a: vendor/a as a splice" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "a: vendor/a as a splice" ]
}

@test "clone --from-submodule: removes .gitmodules once empty, and the submodule's config" {
  add_submodule
  splice clone --from-submodule vendor/a
  ! git cat-file -e HEAD:.gitmodules
  [ ! -e .gitmodules ]
  [ -z "$(git config --get-regexp '^submodule\.' || true)" ]
}

@test "clone --from-submodule: keeps the other submodules in .gitmodules" {
  add_submodule
  git -c protocol.file.allow=always submodule add -q "$upstream" vendor/b
  git commit -q -m "add vendor/b as a submodule"
  splice clone --from-submodule vendor/a
  [ "$(git config --file .gitmodules --get-regexp '\.path$')" = "submodule.vendor/b.path vendor/b" ]
  [ "$(path_mode HEAD vendor/b)" = 160000 ]
}

@test "clone --from-submodule: without a branch in .gitmodules, pins the submodule's commit, not upstream's newest" {
  add_submodule
  local pinned
  pinned="$(git rev-parse HEAD:vendor/a)"
  seed_bare_repo "$upstream" "newer"
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"===  vendor/a: pinned at ${pinned:0:7}, as the submodule was -- pull brings in nothing and push refuses on main until it follows a branch: git config --file vendor/a/.splice --unset upstream.origin.default-pin"* ]]
  [ "$(splice_config vendor/a commit)" = "$pinned" ]
  [ "$(upstream_config vendor/a origin default-pin)" = "$pinned" ]
  [ "$(cat vendor/a/file.txt)" = seed ]
  [ "$(splice_state vendor/a)" = up-to-date ]
  git config --file vendor/a/.splice --unset upstream.origin.default-pin
  git commit -q -m "vendor/a: follow main" -- vendor/a/.splice
  [ "$(splice_state vendor/a)" = pull ]
}

@test "clone --from-submodule: a commit only a tag has is pinned, and the hint names the tag" {
  add_submodule
  local tmp="$BATS_TEST_TMPDIR/release-work" pinned
  git clone -q "$upstream" "$tmp"
  git -C "$tmp" commit -q --allow-empty -m "release 1.0"
  git -C "$tmp" tag -a -m "1.0" 1.0
  git -C "$tmp" push -q origin 1.0
  pinned="$(git -C "$tmp" rev-parse HEAD)"
  git -C vendor/a fetch -q origin tag 1.0
  git -C vendor/a checkout -q 1.0
  git commit -q -a -m "vendor/a: 1.0"
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"===  vendor/a: pinned at ${pinned:0:7}, the tag '1.0', as the submodule was"* ]]
  [ "$(upstream_config vendor/a origin default-pin)" = "$pinned" ]
}

@test "clone --from-submodule: a submodule that was never checked out gets its files" {
  add_submodule
  git clone -q "$monorepo" "$BATS_TEST_TMPDIR/colleague"
  cd "$BATS_TEST_TMPDIR/colleague"
  [ -z "$(ls -A vendor/a)" ]
  run splice clone --from-submodule vendor/a
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
  run splice clone --from-submodule vendor/a
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
  splice clone --from-submodule vendor/a
  [ ! -e vendor/a/.git ]
  git --git-dir=.git/modules/vendor/a rev-parse --verify --quiet local-work
}

@test "clone --from-submodule: warns about settings a splice has no equivalent for" {
  add_submodule
  git config --file .gitmodules submodule.vendor/a.update rebase
  git config --file .gitmodules submodule.vendor/a.shallow true
  git commit -q -a -m "submodule settings"
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: dropping submodule.vendor/a.update from .gitmodules"* ]]
  [[ "$output" == *"vendor/a: dropping submodule.vendor/a.shallow from .gitmodules"* ]]
}

@test "clone --from-submodule: the branch a submodule follows becomes default-branch" {
  add_submodule
  git config --file .gitmodules submodule.vendor/a.branch release
  git commit -q -a -m "follow release"
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" != *"dropping submodule.vendor/a.branch"* ]]
  [[ "$output" != *"pinned at"* ]]
  [ "$(upstream_config vendor/a origin default-branch)" = release ]
}

@test "clone --from-submodule: a branch of \".\" or the monorepo's default branch's name records no default-branch or default-pin" {
  add_submodule
  git config --file .gitmodules submodule.vendor/a.branch .
  git commit -q -a -m "follow the same branch"
  splice clone --from-submodule vendor/a
  [ -z "$(upstream_config vendor/a origin default-branch)$(upstream_config vendor/a origin default-pin)" ]
  git -c protocol.file.allow=always submodule add -q "$upstream" vendor/b
  git config --file .gitmodules submodule.vendor/b.branch main
  git commit -q -a -m "add vendor/b, following main"
  splice clone --from-submodule vendor/b
  [ -z "$(upstream_config vendor/b origin default-branch)$(upstream_config vendor/b origin default-pin)" ]
}

@test "clone --from-submodule: refuses a commit upstream doesn't serve" {
  add_submodule
  echo "local" >>vendor/a/file.txt
  git -C vendor/a commit -q -a -m "unpushed"
  git add vendor/a && git commit -q -m "bump vendor/a"
  local before
  before="$(git rev-parse HEAD)"
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: upstream doesn't serve the submodule's commit"*"push it to a branch or a tag there first"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -e vendor/a/.git ]
}

@test "clone --from-submodule: refuses a checkout with changes, or at another commit" {
  add_submodule
  echo "edit" >>vendor/a/file.txt
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: the submodule's checkout has changes"* ]]

  git -C vendor/a checkout -q -- file.txt
  echo "new" >vendor/a/untracked.txt
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: the submodule's checkout has changes"* ]]

  rm vendor/a/untracked.txt
  git -C vendor/a commit -q --allow-empty -m "moved on"
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: the submodule's checkout isn't at"* ]]
  [ "$(path_mode HEAD vendor/a)" = 160000 ]
}

@test "clone --from-submodule: an edit status doesn't show, behind assume-unchanged, is kept" {
  add_submodule
  git -C vendor/a update-index --assume-unchanged file.txt
  echo "local tuning" >vendor/a/file.txt
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/file.txt)" = "local tuning" ]
  [ "$(git show HEAD:vendor/a/file.txt)" = seed ]
  [ "$(git status --porcelain)" = " M vendor/a/file.txt" ]
}

@test "clone --from-submodule: a deletion behind assume-unchanged comes back, as the help says" {
  add_submodule
  git -C vendor/a update-index --assume-unchanged file.txt
  rm vendor/a/file.txt
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/file.txt)" = seed ]
}

@test "clone --from-submodule: refuses an ignored .splice in the checkout" {
  add_submodule
  echo ".splice" >"$BATS_TEST_TMPDIR/exclude"
  git -C vendor/a config core.excludesFile "$BATS_TEST_TMPDIR/exclude"
  echo "mine" >vendor/a/.splice
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/.splice exists in the submodule's checkout -- move it away first"* ]]
  [ "$(cat vendor/a/.splice)" = mine ]
  [ "$(path_mode HEAD vendor/a)" = 160000 ]
}

@test "clone --from-submodule: refuses staged changes and uncommitted .gitmodules edits" {
  add_submodule
  echo "app" >app.txt && git add app.txt
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"there are staged changes"* ]]

  git rm -q --cached app.txt
  git config --file .gitmodules submodule.vendor/a.branch release
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *".gitmodules has uncommitted changes"* ]]
}

# Makes upstream a repository with a submodule of its own, inner.git at
# libs/inner, and commits it as a submodule at vendor/a.
add_nested_submodule() {
  inner="$BATS_TEST_TMPDIR/inner.git"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "inner"
  add_upstream_submodule "$upstream" "$inner" libs/inner
  add_submodule
}

# As add_nested_submodule, with branch = $1 for libs/inner in upstream's
# .gitmodules, and a branch stable in inner.git.
add_nested_submodule_with_branch() {
  inner="$BATS_TEST_TMPDIR/inner.git"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "inner"
  git -C "$inner" branch stable main
  local tmp
  tmp="$(mktemp -d)"
  git clone -q "$upstream" "$tmp"
  (
    cd "$tmp"
    git -c protocol.file.allow=always submodule add -q "$inner" libs/inner
    git config --file .gitmodules submodule.libs/inner.branch "$1"
    git add .gitmodules
    git commit -q -m "add libs/inner as a submodule"
    git push -q origin HEAD:main
  )
  rm -rf "$tmp"
  add_submodule
}

@test "clone --from-submodule: refuses a submodule with submodules of its own, naming --recursive" {
  add_nested_submodule
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: the submodule has a submodule of its own, libs/inner -- turn it into a splice in its upstream first, or add --recursive to convert it here too"* ]]
  [ "$(path_mode HEAD vendor/a)" = 160000 ]
}

@test "clone --from-submodule --recursive: refuses -m, which names one commit" {
  add_nested_submodule
  run splice clone --from-submodule --recursive -m "a: both" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"-m names one commit, and --recursive makes one per submodule"* ]]
  [ "$(path_mode HEAD vendor/a)" = 160000 ]
}

@test "clone --from-submodule --recursive: converts the nested submodule too, in a commit of its own" {
  add_nested_submodule
  local before outer_pin inner_pin
  before="$(git rev-parse HEAD)"
  outer_pin="$(git rev-parse HEAD:vendor/a)"
  inner_pin="$(git -C "$upstream" rev-parse main:libs/inner)"
  run splice clone --from-submodule --recursive vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a: cloned ${outer_pin:0:7} from the submodule"* ]]
  [[ "$output" == *"ok   vendor/a/libs/inner: cloned ${inner_pin:0:7} from the submodule"* ]]
  [[ "$output" == *"vendor/a: upstream still has libs/inner as a submodule -- 'git splice push vendor/a' turns it into a splice there too"* ]]
  [ "$(git rev-parse HEAD~2)" = "$before" ]
  [ "$(git log -1 --format=%s HEAD^)" = "splice: clone vendor/a from submodule at ${outer_pin:0:7}" ]
  [ "$(git log -1 --format=%s)" = "splice: clone vendor/a/libs/inner from submodule at ${inner_pin:0:7}" ]
  [ "$(path_mode HEAD vendor/a/libs/inner)" = 040000 ]
  [ "$(cat vendor/a/libs/inner/file.txt)" = inner ]
  [ "$(git config --file vendor/a/libs/inner/.splice upstream.origin.url)" = "$inner" ]
  [ "$(splice_config vendor/a/libs/inner commit)" = "$inner_pin" ]
  [ "$(splice_config vendor/a commit)" = "$outer_pin" ]
  ! git cat-file -e HEAD:vendor/a/.gitmodules
  [ -z "$(git status --porcelain)" ]
  [ "$(splice_state vendor/a/libs/inner)" = up-to-date ]
  [ "$(splice_state vendor/a)" = push ]
}

@test "clone --from-submodule --recursive: the push turns the submodule into a splice upstream too" {
  add_nested_submodule
  local outer_pin
  outer_pin="$(git rev-parse HEAD:vendor/a)"
  splice clone --from-submodule --recursive vendor/a
  git config --file vendor/a/.splice --unset upstream.origin.default-pin
  git commit -q -m "vendor/a: follow main" -- vendor/a/.splice
  run splice push vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" rev-parse main^)" = "$outer_pin" ]
  [ "$(git -C "$upstream" log -1 --format=%s main)" = "splice: clone vendor/a/libs/inner from submodule at $(git -C "$upstream" rev-parse --short=7 "$outer_pin:libs/inner")" ]
  [ "$(git -C "$upstream" ls-tree main libs/inner | cut -c1-6)" = 040000 ]
  git -C "$upstream" cat-file -e main:libs/inner/.splice
  ! git -C "$upstream" cat-file -e main:.gitmodules
  ! git -C "$upstream" cat-file -e main:.splice
  [ "$(git -C "$upstream" rev-parse main:libs/inner/.splice)" = "$(git rev-parse HEAD:vendor/a/libs/inner/.splice)" ]
  splice fetch
  [ "$(splice_state vendor/a)" = up-to-date ]
}

@test "clone --from-submodule --recursive: a relative URL is relative to the upstream above" {
  inner="$BATS_TEST_TMPDIR/inner.git"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "inner"
  add_upstream_submodule "$upstream" ../inner.git libs/inner
  git remote add origin https://git.example.com/org/mono.git
  add_submodule
  splice clone --from-submodule --recursive vendor/a
  [ "$(git config --file vendor/a/libs/inner/.splice upstream.origin.url)" = "$BATS_TEST_TMPDIR/inner.git" ]
}

@test "clone --from-submodule --recursive: converts every level, top-down" {
  local deep="$BATS_TEST_TMPDIR/deep.git"
  make_bare_repo "$deep"
  seed_bare_repo "$deep" "deep"
  inner="$BATS_TEST_TMPDIR/inner.git"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "inner"
  add_upstream_submodule "$inner" "$deep" deep
  add_upstream_submodule "$upstream" "$inner" libs/inner
  add_submodule
  splice clone --from-submodule --recursive vendor/a
  [ "$(cat vendor/a/libs/inner/deep/file.txt)" = deep ]
  [ "$(git log -3 --format=%s | cut -d' ' -f3)" = "$(printf '%s\n' vendor/a/libs/inner/deep vendor/a/libs/inner vendor/a)" ]
  [ -z "$(git status --porcelain)" ]
  [ "$(splice_state vendor/a/libs/inner)" = push ]
  [ "$(splice_state vendor/a/libs/inner/deep)" = up-to-date ]
}

@test "clone --from-submodule --recursive: the same upstream twice makes two splices, each at its own commit" {
  add_nested_submodule
  git -c protocol.file.allow=always submodule add -q "$inner" vendor/inner
  git commit -q -m "add vendor/inner as a submodule"
  seed_bare_repo "$inner" "newer"
  git -C vendor/inner pull -q origin main
  git commit -q -a -m "bump vendor/inner"
  splice clone --from-submodule vendor/inner
  splice clone --from-submodule --recursive vendor/a
  [ "$(cat vendor/inner/file.txt)" = "$(printf 'inner\nnewer')" ]
  [ "$(cat vendor/a/libs/inner/file.txt)" = inner ]
  [ "$(splice_state vendor/inner)" = up-to-date ]
  [ "$(splice_state vendor/a/libs/inner)" = up-to-date ]
  [ "$(upstream_config vendor/a/libs/inner origin default-pin)" != "$(upstream_config vendor/inner origin default-pin)" ]
}

@test "clone --from-submodule --recursive: the fetch doesn't look for upstream's submodules in the monorepo" {
  add_nested_submodule
  # As git clone --recurse-submodules leaves it: every submodule is active.
  git config submodule.active .
  run splice clone --from-submodule --recursive vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" != *"Could not access submodule"* ]]
}

@test "clone --from-submodule --recursive: nested checkouts lose their .git, their repositories stay" {
  add_nested_submodule
  git -c protocol.file.allow=always submodule -q update --init --recursive
  [ -e vendor/a/libs/inner/.git ]
  run splice clone --from-submodule --recursive vendor/a
  [ "$status" -eq 0 ]
  [ ! -e vendor/a/.git ]
  [ ! -e vendor/a/libs/inner/.git ]
  [ -d .git/modules/vendor/a/modules/libs/inner ]
  [[ "$output" == *"vendor/a/libs/inner: the submodule's repository stays in $monorepo/.git/modules/vendor/a/modules/libs/inner"* ]]
  [ -z "$(git status --porcelain)" ]
}

@test "clone --from-submodule --recursive: a refused nested submodule leaves the one above converted, and clone on it resumes" {
  add_nested_submodule
  # The nested submodule's commit is on no branch upstream.
  local tmp="$BATS_TEST_TMPDIR/outer-work"
  git clone -q "$upstream" "$tmp"
  git -C "$tmp" -c protocol.file.allow=always submodule -q update --init
  git -C "$tmp/libs/inner" commit -q --allow-empty -m "unpushed"
  git -C "$tmp" commit -q -a -m "bump libs/inner"
  git -C "$tmp" push -q origin main
  git -C vendor/a pull -q origin main
  git commit -q -a -m "bump vendor/a"
  run splice clone --from-submodule --recursive vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/libs/inner: upstream doesn't serve the submodule's commit"* ]]
  [[ "$output" == *"vendor/a/libs/inner: not converted -- vendor/a and what was converted before stay; fix the above, then run 'git splice clone --from-submodule --recursive vendor/a/libs/inner'"* ]]
  [ "$(path_mode HEAD vendor/a)" = 040000 ]
  [ "$(path_mode HEAD vendor/a/libs/inner)" = 160000 ]

  git -C "$tmp/libs/inner" push -q origin HEAD:main
  run splice clone --from-submodule --recursive vendor/a/libs/inner
  [ "$status" -eq 0 ]
  [ "$(path_mode HEAD vendor/a/libs/inner)" = 040000 ]
  [ -z "$(git status --porcelain)" ]
}

@test "clone: --recursive needs --from-submodule" {
  run splice clone --recursive "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"--recursive needs --from-submodule"* ]]
}

@test "clone --from-submodule: refuses a path that is no submodule, and --merge" {
  mkdir -p vendor/b && echo x >vendor/b/x.txt && git add vendor && git commit -q -m b
  run splice clone --from-submodule vendor/b
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/b: no submodule committed here"* ]]

  add_submodule
  run splice clone --merge --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"--from-submodule takes no --merge"* ]]
}

@test "clone: names --from-submodule for a path that is a submodule" {
  add_submodule
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a is a submodule -- 'git splice clone --from-submodule vendor/a' turns it into a splice"* ]]
}

@test "clone --from-submodule: records the branch the submodule follows, also where upstream's default branch is named differently" {
  local other="$BATS_TEST_TMPDIR/other.git"
  make_bare_repo "$other" master
  seed_bare_repo "$other" "seed" master
  git -c protocol.file.allow=always submodule add -q -b master "$other" vendor/a
  git commit -q -m "add vendor/a as a submodule"
  splice clone --from-submodule vendor/a
  [ "$(upstream_config vendor/a origin default-branch)" = master ]
}

# Prints the URL `git splice clone --from-submodule` makes of submodule URL
# $1, which goes into the key it records before it fetches. The fetch fails,
# as no protocol is allowed: none of these URLs is real.
resolved_submodule_url() {
  local url="$1"
  git config --file .gitmodules submodule.s.path s
  git config --file .gitmodules submodule.s.url "$url"
  git add .gitmodules
  git update-index --add --cacheinfo "160000,$(git rev-parse HEAD),s"
  git commit -q --allow-empty -m "s at $url"
  GIT_ALLOW_PROTOCOL=none splice clone --from-submodule s >/dev/null 2>&1 || true
  git config --local --get-regexp '^splice\..*\.url$' | cut -d' ' -f2-
  git config --local --remove-section "$(git config --local --name-only --get-regexp '^splice\..*\.url$' | sed 's/\.url$//')"
}

@test "clone --from-submodule: relative URLs, as git submodule reads them" {
  git remote add origin https://git.example.com/org/mono.git
  [ "$(resolved_submodule_url https://other.example.com/lib.git)" = https://other.example.com/lib.git ]
  [ "$(resolved_submodule_url ../lib.git)" = https://git.example.com/org/lib.git ]
  [ "$(resolved_submodule_url ./lib.git)" = https://git.example.com/org/mono.git/lib.git ]
  [ "$(resolved_submodule_url ../../other/lib.git)" = https://git.example.com/other/lib.git ]
  git remote set-url origin git@git.example.com:org/mono.git
  [ "$(resolved_submodule_url ../lib.git)" = git@git.example.com:org/lib.git ]
  git remote set-url origin host:mono.git
  [ "$(resolved_submodule_url ../lib.git)" = host:lib.git ]
  git remote set-url origin git@git.example.com:/mono.git
  [ "$(resolved_submodule_url ../lib.git)" = git@git.example.com:/lib.git ]
  git remote set-url origin https://git.example.com
  [ "$(resolved_submodule_url ../lib.git)" = https://lib.git ]
}

@test "clone --from-submodule: resolves a relative URL in a SHA-256 monorepo, whatever new repositories default to" {
  git init -q -b main --object-format=sha256 "$BATS_TEST_TMPDIR/sha256"
  cd "$BATS_TEST_TMPDIR/sha256"
  git config user.name Test
  git config user.email test@example.com
  git commit -q --allow-empty -m "initial commit"
  git remote add origin https://git.example.com/org/mono.git
  [ "$(resolved_submodule_url ../lib.git)" = https://git.example.com/org/lib.git ]
}

@test "clone --from-submodule: a remote URL that is a relative path is relative to the monorepo" {
  git remote add origin mono.git
  [ "$(resolved_submodule_url ../lib.git)" = "$monorepo/lib.git" ]
  git remote set-url origin ../mono.git
  [ "$(resolved_submodule_url ../lib.git)" = "$monorepo/../lib.git" ]
}

@test "clone --from-submodule: a relative URL uses the current branch's remote first, the monorepo itself without one" {
  [ "$(resolved_submodule_url ../lib.git)" = "$BATS_TEST_TMPDIR/lib.git" ]
  git remote add origin https://git.example.com/org/mono.git
  git remote add fork https://git.example.com/me/mono.git
  git config branch.main.remote fork
  [ "$(resolved_submodule_url ../lib.git)" = https://git.example.com/me/lib.git ]
}

@test "clone --from-submodule: resolves a relative URL and records it absolute" {
  git remote add origin "$BATS_TEST_TMPDIR/mono.git"
  git -c protocol.file.allow=always submodule add -q ../upstream.git vendor/a
  git commit -q -m "add vendor/a as a submodule"
  splice clone --from-submodule vendor/a
  [ "$(git config --file vendor/a/.splice upstream.origin.url)" = "$BATS_TEST_TMPDIR/upstream.git" ]
}

@test "clone --from-submodule: a branch that still has the submodule merges the conversion cleanly" {
  add_submodule
  git checkout -q -b feature
  echo "app" >app.txt && git add app.txt && git commit -q -m "app"
  git checkout -q main
  splice clone --from-submodule vendor/a
  git checkout -q feature
  git merge -q --no-edit main
  [ "$(path_mode HEAD vendor/a)" = 040000 ]
  [ "$(cat vendor/a/file.txt)" = seed ]
  [ "$(cat app.txt)" = app ]
  [ -z "$(git status --porcelain)" ]
}

@test "clone --from-submodule: finds the settings of a submodule whose name isn't its path" {
  git -c protocol.file.allow=always submodule add -q --name 'lib+x(1).v2' "$upstream" vendor/a
  git config --file .gitmodules 'submodule.lib+x(1).v2.update' rebase
  git commit -q -a -m "add vendor/a as a submodule"
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"dropping submodule.lib+x(1).v2.update from .gitmodules"* ]]
  [[ "$output" != *"dropping submodule.lib+x(1).v2.url"* ]]
  [ ! -e .gitmodules ]
}

@test "clone --from-submodule: refuses a .gitmodules edit status doesn't show, behind assume-unchanged" {
  add_submodule
  git update-index --assume-unchanged .gitmodules
  echo "# my notes" >>.gitmodules
  run splice clone --from-submodule vendor/a
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
  run splice clone --from-submodule vendor/a
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
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: a file takes the place of the uninitialized submodule"* ]]
  [ "$(cat vendor/a)" = notes ]

  rm vendor/a && mkdir empty && ln -s ../empty vendor/a
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: a symbolic link takes the submodule's place"* ]]
  [ -L vendor/a ]
  [ -z "$(git for-each-ref refs/splices/)" ]
  git diff --cached --quiet
}

@test "clone --from-submodule: refuses a submodule below a symbolic link, before fetching" {
  add_submodule
  git clone -q "$monorepo" "$BATS_TEST_TMPDIR/colleague"
  cd "$BATS_TEST_TMPDIR/colleague"
  mkdir -p "$BATS_TEST_TMPDIR/outside/a"
  rm -r vendor && ln -s "$BATS_TEST_TMPDIR/outside" vendor
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: vendor is a symbolic link -- the submodule's folder must be inside the repository"* ]]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/outside/a")" ]
  [ -z "$(git for-each-ref refs/splices/)" ]
}

@test "clone --from-submodule: a submodule never checked out, at a commit without files, gets its folder" {
  local empty="$BATS_TEST_TMPDIR/empty.git" tmp="$BATS_TEST_TMPDIR/empty-seed"
  make_bare_repo "$empty"
  git init -q -b main "$tmp"
  git -C "$tmp" commit -q --allow-empty -m "empty"
  git -C "$tmp" push -q "$empty" main
  git -c protocol.file.allow=always submodule add -q "$empty" vendor/a
  git commit -q -m "add vendor/a as a submodule"
  git clone -q "$monorepo" "$BATS_TEST_TMPDIR/colleague"
  cd "$BATS_TEST_TMPDIR/colleague"
  rmdir vendor/a
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [ "$(ls -A vendor/a)" = .splice ]
  [ -z "$(git status --porcelain)" ]
}

@test "clone --from-submodule --recursive: upstream moving on, its submodule unchanged, pulls and then pushes" {
  add_nested_submodule
  splice clone --from-submodule --recursive vendor/a
  git config --file vendor/a/.splice --unset upstream.origin.default-pin
  git commit -q -m "vendor/a: follow main" -- vendor/a/.splice
  seed_bare_repo "$upstream" "upstream moved on"
  splice fetch
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(path_mode HEAD vendor/a/libs/inner)" = 040000 ]
  [ "$(tail -1 vendor/a/file.txt)" = "upstream moved on" ]
  run splice push vendor/a
  [ "$status" -eq 0 ]
  [ "$(git -C "$upstream" ls-tree main libs/inner | cut -c1-6)" = 040000 ]
}

@test "clone --from-submodule --recursive: upstream moving its submodule before the push is refused on pull" {
  add_nested_submodule
  splice clone --from-submodule --recursive vendor/a
  git config --file vendor/a/.splice --unset upstream.origin.default-pin
  git commit -q -m "vendor/a: follow main" -- vendor/a/.splice
  seed_bare_repo "$inner" "newer"
  local tmp="$BATS_TEST_TMPDIR/outer-work"
  git clone -q "$upstream" "$tmp"
  git -C "$tmp" -c protocol.file.allow=always submodule -q update --init --remote
  git -C "$tmp" commit -q -a -m "bump libs/inner"
  git -C "$tmp" push -q origin main
  splice fetch
  local before
  before="$(git rev-parse HEAD)"
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: upstream has a submodule, libs/inner, which nobody could check out in the monorepo"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "clone --from-submodule --recursive: a refusal two levels down names only the submodule refused" {
  local deep="$BATS_TEST_TMPDIR/deep.git"
  make_bare_repo "$deep"
  seed_bare_repo "$deep" "deep"
  inner="$BATS_TEST_TMPDIR/inner.git"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "inner"
  add_upstream_submodule "$inner" "$deep" deep
  # deep's commit is on no branch upstream.
  local tmp="$BATS_TEST_TMPDIR/inner-work"
  git clone -q "$inner" "$tmp"
  git -C "$tmp" -c protocol.file.allow=always submodule -q update --init
  git -C "$tmp/deep" commit -q --allow-empty -m "unpushed"
  git -C "$tmp" commit -q -a -m "bump deep"
  git -C "$tmp" push -q origin main
  add_upstream_submodule "$upstream" "$inner" libs/inner
  add_submodule
  run splice clone --from-submodule --recursive vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/libs/inner/deep: not converted -- vendor/a/libs/inner and what was converted before stay"* ]]
  [[ "$output" != *"vendor/a/libs/inner: not converted"* ]]
  [ "$(path_mode HEAD vendor/a/libs/inner)" = 040000 ]
  [ "$(path_mode HEAD vendor/a/libs/inner/deep)" = 160000 ]
}

@test "clone --from-submodule: an upstream with many tags doesn't stop the conversion while it looks for the pinned commit's tag" {
  add_submodule
  local work pinned
  pinned="$(git rev-parse HEAD:vendor/a)"
  work="$(mktemp -d)"
  git clone -q "$upstream" "$work"
  for i in $(seq 1 3000); do
    printf 'create refs/tags/t%04d %s\n' "$i" "$pinned"
  done | git -C "$work" update-ref --stdin
  git -C "$work" push -q --tags origin
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"===  vendor/a: pinned at ${pinned:0:7}, the tag 't0001', as the submodule was"* ]]
}

@test "clone --from-submodule --recursive: branch = . inside a pinned submodule stays at its commit, as the one above does" {
  add_nested_submodule_with_branch .
  local inner_pin
  inner_pin="$(git -C "$upstream" rev-parse main:libs/inner)"
  run splice clone --from-submodule --recursive vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"===  vendor/a/libs/inner: pinned at ${inner_pin:0:7}, as vendor/a is -- "* ]]
  [ "$(git config --file vendor/a/libs/inner/.splice upstream.origin.default-pin)" = "$inner_pin" ]
  run splice status
  [ "$status" -eq 0 ]
}

@test "clone --from-submodule --recursive: a branch inside a pinned submodule becomes its default-branch" {
  add_nested_submodule_with_branch stable
  run splice clone --from-submodule --recursive vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" != *"!!"* ]]
  [ "$(git config --file vendor/a/libs/inner/.splice upstream.origin.default-branch)" = stable ]
}

@test "clone --from-submodule: refuses to pin when the monorepo's default branch can't be determined" {
  git config --unset init.defaultBranch
  add_submodule
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: the submodule stays at "*", and a pin applies on the monorepo's default branch, which can't be determined -- set it (git config init.defaultBranch <branch>, or git remote set-head origin --auto) and re-run"* ]]
  [ "$(path_mode HEAD vendor/a)" = 160000 ]
}

@test "clone --from-submodule: refuses to record a branch when the monorepo's default branch can't be determined" {
  git config --unset init.defaultBranch
  git -C "$upstream" branch release main
  add_submodule
  git config --file .gitmodules submodule.vendor/a.branch release
  git commit -q -m "vendor/a follows release" .gitmodules
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: the submodule follows 'release', and a default-branch applies on the monorepo's default branch, which can't be determined -- set it (git config init.defaultBranch <branch>, or git remote set-head origin --auto) and re-run"* ]]
  [ "$(path_mode HEAD vendor/a)" = 160000 ]
}

@test "clone --from-submodule: an upstream with tags but no branches converts a submodule at a tag" {
  local pinned
  pinned="$(git -C "$upstream" rev-parse main)"
  git -C "$upstream" tag v1 main
  add_submodule
  git -C "$upstream" update-ref -d refs/heads/main
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"===  vendor/a: pinned at ${pinned:0:7}, the tag 'v1', as the submodule was"* ]]
  [ "$(git config --file vendor/a/.splice upstream.origin.default-pin)" = "$pinned" ]
}

@test "clone --from-submodule --recursive: stops when a hook rejects a nested conversion's commit, which stays staged" {
  add_nested_submodule
  local hooks outer_pin
  outer_pin="$(git rev-parse HEAD:vendor/a)"
  hooks="$(git rev-parse --git-path hooks)"
  mkdir -p "$hooks"
  printf '#!/bin/sh\n! git diff --cached --name-only | grep -q libs/inner/.splice\n' >"$hooks/pre-commit"
  chmod +x "$hooks/pre-commit"
  run splice clone --from-submodule --recursive vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" != *"ok   vendor/a/libs/inner: cloned"* ]]
  [[ "$output" == *"!!   vendor/a/libs/inner: 'git commit' failed -- the conversion stays staged"* ]]
  [ "$(git log -1 --format=%s)" = "splice: clone vendor/a from submodule at ${outer_pin:0:7}" ]
  [ -n "$(git diff --cached --name-only -- vendor/a/libs/inner/.splice)" ]
}

@test "clone --from-submodule: refuses a submodule that update = none keeps out of checkouts" {
  add_submodule
  git config --file .gitmodules submodule.vendor/a.update none
  git commit -q -a -m "keep vendor/a out of checkouts"
  git clone -q "$monorepo" "$BATS_TEST_TMPDIR/colleague"
  cd "$BATS_TEST_TMPDIR/colleague"
  git -c protocol.file.allow=always submodule -q update --init --recursive
  [ -z "$(ls -A vendor/a)" ]
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: update = none keeps the submodule out of every checkout, and a splice's files are always there -- remove the submodule, or unset submodule.vendor/a.update in .gitmodules and commit to splice it anyway"* ]]
  [ "$(path_mode HEAD vendor/a)" = 160000 ]
  [ -z "$(ls -A vendor/a)" ]
}

# As add_nested_submodule, with update = none for libs/inner in upstream's
# .gitmodules: a recursive checkout leaves its folder empty.
add_nested_submodule_update_none() {
  inner="$BATS_TEST_TMPDIR/inner.git"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "inner"
  add_upstream_submodule "$upstream" "$inner" libs/inner
  local tmp
  tmp="$(mktemp -d)"
  git clone -q "$upstream" "$tmp"
  (
    cd "$tmp"
    git config --file .gitmodules submodule.libs/inner.update none
    git commit -q -a -m "keep libs/inner out of checkouts"
    git push -q origin HEAD:main
  )
  rm -rf "$tmp"
  add_submodule
  git -c protocol.file.allow=always submodule -q update --init --recursive
}

@test "clone --from-submodule --recursive: refuses a nested submodule that update = none keeps out of checkouts, the one above converted" {
  add_nested_submodule_update_none
  [ -z "$(ls -A vendor/a/libs/inner)" ]
  run splice clone --from-submodule --recursive vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/libs/inner: update = none keeps the submodule out of every checkout, and a splice's files are always there -- remove the submodule, or unset submodule.libs/inner.update in vendor/a/.gitmodules and commit to splice it anyway"* ]]
  [ "$(path_mode HEAD vendor/a)" = 040000 ]
  [ "$(path_mode HEAD vendor/a/libs/inner)" = 160000 ]
  [ -z "$(ls -A vendor/a/libs/inner)" ]
  [ -z "$(git status --porcelain)" ]
}

@test "clone --from-submodule --recursive: a nested submodule with update = none unset and committed is spliced on resume" {
  add_nested_submodule_update_none
  run splice clone --from-submodule --recursive vendor/a
  [ "$status" -eq 1 ]
  git config --file vendor/a/.gitmodules --unset submodule.libs/inner.update
  git commit -q -a -m "splice libs/inner anyway"
  run splice clone --from-submodule --recursive vendor/a/libs/inner
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/libs/inner/file.txt)" = inner ]
}

# Commits .gitattributes with content $1 to the monorepo.
commit_attributes() {
  printf '%b' "$1" >.gitattributes
  git add .gitattributes
  git commit -q -m "attributes"
}

@test "clone --from-submodule: the monorepo's text=auto stops the conversion too, as git add would store a file someone gives CRLF with LF" {
  commit_raw_file "$upstream" run.bat 'echo hi\r\n'
  commit_attributes '* text=auto\n'
  add_submodule
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"add 'vendor/a/** !text !eol !filter !ident !working-tree-encoding' to .gitattributes"* ]]
}

@test "clone --from-submodule: refuses where the monorepo's attributes would apply to upstream's files, naming the line that unsets them" {
  commit_raw_file "$upstream" run.bat 'echo hi\r\n'
  commit_attributes '*.bat text eol=crlf\n'
  add_submodule
  local before
  before="$(git rev-parse HEAD)"
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: attributes in .gitattributes or above it would change how Git checks out or stores some of its files, unlike in upstream -- add 'vendor/a/** !text !eol !filter !ident !working-tree-encoding' to .gitattributes, commit it, and run clone again"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ "$(path_mode HEAD vendor/a)" = 160000 ]
  [ -z "$(git status --porcelain)" ]
}

@test "clone --from-submodule: with the line it names committed, the conversion keeps files as upstream committed them" {
  commit_raw_file "$upstream" build.bat 'echo build\r\n'
  commit_raw_file "$upstream" run.bat 'echo run\n'
  commit_attributes '*.bat text eol=crlf\nvendor/a/** !text !eol !filter !ident !working-tree-encoding\n'
  add_submodule
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
  [ -z "$(git status --porcelain)" ]
  git clone -q "$monorepo" "$BATS_TEST_TMPDIR/colleague"
  [ "$(od -c "$BATS_TEST_TMPDIR/colleague/vendor/a/run.bat")" = "$(printf 'echo run\n' | od -c)" ]
  [ "$(od -c "$BATS_TEST_TMPDIR/colleague/vendor/a/build.bat")" = "$(printf 'echo build\r\n' | od -c)" ]
}

@test "clone --from-submodule --recursive: refuses where the splice above's attributes would apply to the nested upstream's files, the one above converted; resumes with the line committed there" {
  inner="$BATS_TEST_TMPDIR/inner.git"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "inner"
  commit_raw_file "$inner" settings.h '#define X 1\r\n'
  commit_raw_file "$upstream" .gitattributes '*.h text eol=lf\n'
  add_upstream_submodule "$upstream" "$inner" libs/inner
  add_submodule
  git -c protocol.file.allow=always submodule -q update --init --recursive
  run splice clone --from-submodule --recursive vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a/libs/inner: attributes in vendor/a/.gitattributes or above it would change how Git checks out or stores some of its files, unlike in upstream -- add 'libs/inner/** !text !eol !filter !ident !working-tree-encoding' to vendor/a/.gitattributes, commit it, and run clone again"* ]]
  [ "$(path_mode HEAD vendor/a)" = 040000 ]
  [ "$(path_mode HEAD vendor/a/libs/inner)" = 160000 ]
  echo 'libs/inner/** !text !eol !filter !ident !working-tree-encoding' >>vendor/a/.gitattributes
  git commit -q -a -m "keep the splice's line endings off libs/inner"
  run splice clone --from-submodule --recursive vendor/a/libs/inner
  [ "$status" -eq 0 ]
  [ -z "$(git status --porcelain)" ]
}

@test "clone --from-submodule: the line it names matches only the splice's folder, whatever its name" {
  commit_raw_file "$upstream" run.bat 'echo hi\r\n'
  commit_attributes '*.bat text eol=crlf\n'
  git -c protocol.file.allow=always submodule add -q "$upstream" "#a"
  git commit -q -m "add #a"
  run splice clone --from-submodule "#a"
  [ "$status" -eq 1 ]
  [[ "$output" == *"add '\#a/** !text !eol !filter !ident !working-tree-encoding' to .gitattributes"* ]]
}

@test "clone --from-submodule: the line it names escapes a leading character a .gitattributes line would read otherwise" {
  commit_raw_file "$upstream" run.bat 'echo hi\r\n'
  commit_attributes '*.bat text eol=crlf\n'
  local path expected
  while IFS='|' read -r path expected; do
    git -c protocol.file.allow=always submodule add -q "$upstream" "$path"
    git commit -q -m "add $path"
    run splice clone --from-submodule "$path"
    [ "$status" -eq 1 ]
    [[ "$output" == *"add '$expected !text !eol !filter !ident !working-tree-encoding' to .gitattributes"* ]] || {
      echo "$path: $output, expected $expected"
      return 1
    }
  done <<'TABLE'
vendor/a|vendor/a/**
vendor/#a|vendor/#a/**
#a|\#a/**
!a|\!a/**
"a|\"a/**
TABLE
}

@test "clone --from-submodule: attributes above the submodule that only change tools don't stop the conversion" {
  commit_raw_file "$upstream" run.bat 'echo hi\r\n'
  commit_attributes '*.png binary\n*.c diff=cpp\n'
  add_submodule
  run splice clone --from-submodule vendor/a
  [ "$status" -eq 0 ]
}

@test "clone --from-submodule: stops, committing nothing, when the submodule's repository can't move to .git/modules/" {
  git -c protocol.file.allow=always clone -q "$upstream" vendor/a
  git add vendor/a 2>/dev/null
  git config --file .gitmodules submodule.vendor/a.path vendor/a
  git config --file .gitmodules submodule.vendor/a.url "$upstream"
  git add .gitmodules
  git commit -q -m "add vendor/a as a submodule, its repository embedded"
  mkdir -p .git/modules/vendor/a
  echo taken >.git/modules/vendor/a/file
  local before
  before="$(git rev-parse HEAD)"
  run splice clone --from-submodule vendor/a
  [ "$status" -ne 0 ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -d vendor/a/.git ]
  [ "$(git ls-files --stage vendor/a | cut -d' ' -f1)" = 160000 ]
}

@test "clone --from-submodule: refuses where the monorepo's filter, ident or working-tree-encoding would apply to upstream's files" {
  git config filter.upper.clean "tr a-z A-Z"
  git config filter.upper.smudge cat
  add_submodule
  local attributes
  for attributes in '*.txt filter=upper' '*.txt ident' '*.txt working-tree-encoding=UTF-16LE'; do
    commit_attributes "$attributes\n"
    run splice clone --from-submodule vendor/a
    [ "$status" -eq 1 ] || {
      echo "$attributes: $output"
      return 1
    }
    [[ "$output" == *"add 'vendor/a/** !text !eol !filter !ident !working-tree-encoding' to .gitattributes"* ]]
  done
}
