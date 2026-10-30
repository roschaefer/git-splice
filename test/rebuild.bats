# The push rebuild, checked against `git subtree split` as the test oracle:
# where both apply, the rebuild must make byte-identical commits. Where it
# deliberately differs, the test says so and asserts exactly how ("approved
# divergence"). See docs/design/README.md.

setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load 'scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/03-diverged-then-pulled/setup'
  load 'scenarios/03-branches-and-teamwork/03-squash-merged-pull/setup'
  load 'scenarios/02-starting-a-splice/04-init-new-upstream/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/setup'
  load 'scenarios/04-upstreams/03-shared-remote-url/setup'
  load 'scenarios/06-rewritten-history/04-patch-branch-rebased/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

# A monorepo whose vendor/a was added by `git subtree add --squash`, which
# split understands, and is a splice from the next commit on.
oracle_fixture() {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git subtree add -q --prefix=vendor/a "$upstream" main --squash >/dev/null 2>&1
  git config --file vendor/a/.splice splice.commit "$(git ls-remote "$upstream" refs/heads/main | cut -f1)"
  git config --file vendor/a/.splice splice.id 0123456789abcdef
  git config --file vendor/a/.splice upstream.origin.url "$upstream"
  git add vendor/a/.splice
  git commit -q -m "make vendor/a a splice"
  U="$(splice_config vendor/a commit)"
  fetch_splice "$monorepo" "$upstream" vendor/a
}

# What git subtree split makes of vendor/a, less the state file, which it
# puts in every tree from where the splice starts, and the commit that
# adds it.
split() {
  local split output
  split="$(git -c commit.gpgSign=false subtree split -q --prefix=vendor/a HEAD)" || return 1
  git branch -f split-oracle "$split" || return 1
  output="$(FILTER_BRANCH_SQUELCH_WARNING=1 git -c commit.gpgSign=false filter-branch -f --prune-empty \
    --index-filter 'git rm -q --cached --ignore-unmatch .splice' split-oracle 2>&1)" || {
    printf '%s\n' "$output" >&2
    return 1
  }
  git rev-parse split-oracle
}

@test "rebuild: a linear history rebuilds into exactly the commits git subtree split makes" {
  oracle_fixture
  commit_local "$monorepo" "vendor/a" "first"
  commit_local "$monorepo" "." "outside the splice" outside.txt
  (
    echo both >>vendor/a/file.txt
    echo both >>outside.txt
    git commit -q -am "touches the splice and outside"
  )
  commit_local "$monorepo" "vendor/a" "second" sub/dir/file.txt
  local rebuilt
  rebuilt="$(splice rebuild vendor/a)"
  [ "$(git rev-list --count "$U..$rebuilt")" -eq 3 ]
  [ "$rebuilt" = "$(split)" ]
}

@test "rebuild: approved divergence: a merge in the monorepo becomes one ordinary commit" {
  oracle_fixture
  git checkout -q -b feature
  commit_local "$monorepo" "vendor/a" "feature work" feature.txt
  local before_merge
  before_merge="$(splice rebuild vendor/a)"
  git checkout -q main
  commit_local "$monorepo" "vendor/a" "main work" main.txt
  git checkout -q feature
  git merge -q --no-edit main
  commit_local "$monorepo" "vendor/a" "after the merge" feature.txt

  local ours theirs
  ours="$(splice rebuild vendor/a)"
  theirs="$(split)"
  # Up to the merge, both are the same commits.
  [ "$(git rev-parse "$theirs~2")" = "$before_merge" ]
  [ "$(git rev-parse "$ours~2")" = "$before_merge" ]
  # split keeps the merge, and "main work" as its own commit...
  [ "$(git rev-list --count --merges "$theirs")" -eq 1 ]
  git log --format=%s "$theirs" | grep -qx "main work"
  # ...the rebuild has one commit that carries main's change.
  [ "$(git rev-list --count --merges "$ours")" -eq 0 ]
  ! git log --format=%s "$ours" | grep -qx "main work"
  [ "$(git log -1 --format=%s "$ours~1")" = "Merge branch 'main' into feature" ]
  git cat-file -e "$ours~1:main.txt"
  # Same content in the end.
  [ "$(git rev-parse "$ours^{tree}")" = "$(git rev-parse "$theirs^{tree}")" ]
}

@test "rebuild: keeps file names with newlines, quotes and non-ASCII characters" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local name
  for name in $'line\nbreak' '"quoted' 'tab\there' 'ünïcode'; do
    echo x >"vendor/a/$name"
  done
  git add vendor/a
  git commit -q -m "odd names"
  local rebuilt
  rebuilt="$(splice rebuild vendor/a)"
  # The only difference to the monorepo's folder is the state file.
  [ "$(git diff --name-only "$rebuilt" HEAD:vendor/a)" = ".splice" ]
  [ "$(git ls-tree --name-only -z "$rebuilt" | tr -cd '\0' | wc -c)" -eq 5 ]
}

@test "rebuild: is deterministic, even when commits would be signed" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config commit.gpgSign true
  local first
  first="$(splice rebuild vendor/a)"
  [ -n "$first" ]
  [ "$(splice rebuild vendor/a)" = "$first" ]
}

@test "rebuild: is the same whatever i18n.commitEncoding or i18n.logOutputEncoding say, so users with different settings agree on it" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  commit_local "$monorepo" "vendor/a" "änderung"
  local plain
  plain="$(splice rebuild vendor/a)"
  git config i18n.commitEncoding ISO-8859-1
  [ "$(splice rebuild vendor/a)" = "$plain" ]
  git config --unset i18n.commitEncoding
  git config i18n.logOutputEncoding ISO-8859-1
  [ "$(splice rebuild vendor/a)" = "$plain" ]
  [ "$(git cat-file commit "$plain" | tail -1)" = "änderung" ]
}

@test "rebuild: a pull that merged local changes is copied the same whatever i18n.commitEncoding says" {
  scenario_diverged_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  local plain
  plain="$(splice rebuild vendor/a)"
  git config i18n.commitEncoding ISO-8859-1
  [ "$(splice rebuild vendor/a)" = "$plain" ]
}

@test "rebuild: log.showSignature doesn't change where a splice's history starts" {
  command -v ssh-keygen >/dev/null || skip "no ssh-keygen to sign a commit with"
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  ssh-keygen -q -t ed25519 -N "" -f "$BATS_TEST_TMPDIR/key"
  git config gpg.format ssh
  git config user.signingKey "$BATS_TEST_TMPDIR/key.pub"
  local before boundary
  before="$(splice rebuild vendor/a)"
  git config --file vendor/a/.splice upstream.origin.default-branch main
  git commit -q -S -am "a signed commit that changes .splice"
  boundary="$(splice boundary vendor/a)"
  git config log.showSignature true
  [ "$(splice boundary vendor/a)" = "$boundary" ]
  [ "$(splice rebuild vendor/a)" = "$before" ]
}

@test "rebuild: starts at the synced commit and leaves .splice out" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt
  rebuilt="$(splice rebuild vendor/a)"
  [ "$(git rev-parse "$rebuilt^")" = "$(splice_config vendor/a commit)" ]
  [ "$(git log -1 --format=%s "$rebuilt")" = "local change" ]
  ! git cat-file -e "$rebuilt:.splice" 2>/dev/null
}

@test "rebuild: is the synced commit itself when nothing changed locally" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git switch -q --detach HEAD^
  [ "$(splice rebuild vendor/a)" = "$(splice_config vendor/a commit)" ]
}

@test "rebuild: after init, the history starts at the init commit: earlier commits aren't published" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  printf '[splice]\n\tid = 0123456789abcdef\n[upstream "origin"]\n\turl = %s\n' "$upstream" >lib/a/.splice
  git add lib/a/.splice
  git commit -q -m "init lib/a"
  commit_local "$monorepo" lib/a "third version"
  local rebuilt
  rebuilt="$(splice rebuild lib/a)"
  [ "$(git log --format=%s "$rebuilt")" = "third version"$'\n'"init lib/a" ]
  content_tree "HEAD~1" lib/a
  [ "$(git rev-parse "$rebuilt~1^{tree}")" = "$CONTENT_TREE" ]
  [ -z "$(git rev-parse "$rebuilt~1^@")" ]
}

@test "rebuild: a pull that merged a divergence keeps the unpushed commit and joins upstream with a merge" {
  scenario_diverged_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt synced
  rebuilt="$(splice rebuild vendor/a)"
  synced="$(splice_config vendor/a commit)"
  [ "$(git rev-parse "$rebuilt^2")" = "$synced" ]
  [ "$(git log -1 --format=%s "$rebuilt^1")" = "local change" ]
  [ "$(git rev-parse "$rebuilt^1^")" = "$(git rev-parse "$synced^")" ]
}

@test "rebuild: approved divergence: a squash-merged pull doesn't repeat upstream's commit" {
  scenario_squash_merged_pull "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt feature_tip
  rebuilt="$(splice rebuild vendor/a)"
  feature_tip="$(git rev-parse "$(upstream_refs "$upstream")feature")"
  # The squash merge is the boundary: the rebuild starts at the pulled
  # upstream commit itself, then only the local change follows.
  [ "$(git rev-parse "$rebuilt^")" = "$feature_tip" ]
  [ "$(git log -1 --format=%s "$rebuilt")" = "c: local change" ]
  [ "$(git log --format=%s "$rebuilt" | grep -c "upstream feature work")" -eq 1 ]
}

@test "rebuild: a rebased pull still starts at its synced commit" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  seed_bare_repo "$upstream" "upstream feature work" feature
  cd "$monorepo"
  git checkout -q -b feature
  splice pull vendor/a >/dev/null 2>&1
  commit_local "$monorepo" "vendor/a" "local change"
  git checkout -q main
  commit_local "$monorepo" "." "meanwhile on main" other.txt
  git checkout -q feature
  local pulled
  pulled="$(git rev-parse HEAD^)"
  git rebase -q main
  [ "$(git rev-parse HEAD^)" != "$pulled" ]
  local rebuilt
  rebuilt="$(splice rebuild vendor/a)"
  [ "$(git log -1 --format=%s "$rebuilt")" = "local change" ]
  [ "$(git rev-parse "$rebuilt^")" = "$(git rev-parse "$(upstream_refs "$upstream")feature")" ]
}

# Two splices with their own upstreams, vendor/a and vendor/b, each with
# an unpushed commit.
two_splices_ahead() {
  make_bare_repo "$BATS_TEST_TMPDIR/a.git"
  seed_bare_repo "$BATS_TEST_TMPDIR/a.git" "seed a"
  make_bare_repo "$BATS_TEST_TMPDIR/b.git"
  seed_bare_repo "$BATS_TEST_TMPDIR/b.git" "seed b"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$BATS_TEST_TMPDIR/a.git" vendor/a
  add_splice "$monorepo" "$BATS_TEST_TMPDIR/b.git" vendor/b
  commit_local "$monorepo" vendor/a "not for b's upstream" a.txt
  commit_local "$monorepo" vendor/b "unpushed in b" b.txt
}

@test "rebuild: two splices that swap paths each keep their own history, by their ids" {
  two_splices_ahead
  cd "$monorepo"
  local a b
  a="$(splice rebuild vendor/a)"
  b="$(splice rebuild vendor/b)"
  git mv vendor/a tmp
  git mv vendor/b vendor/a
  git mv tmp vendor/b
  git commit -q -m "swap a and b"
  [ "$(splice rebuild vendor/a)" = "$b" ]
  [ "$(splice rebuild vendor/b)" = "$a" ]
}

@test "rebuild: two splices of the same upstream that swap paths each keep their own history" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "unpushed in a" a.txt
  commit_local "$monorepo" vendor/b "unpushed in b" b.txt
  cd "$monorepo"
  local a b
  a="$(splice rebuild vendor/a)"
  b="$(splice rebuild vendor/b)"
  git mv vendor/a tmp
  git mv vendor/b vendor/a
  git mv tmp vendor/b
  git commit -q -m "swap a and b"
  [ "$(splice rebuild vendor/a)" = "$b" ]
  [ "$(splice rebuild vendor/b)" = "$a" ]
}

@test "rebuild: splices of different upstreams cloned at the same path on branches from the same commit don't get each other's history" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  local other="$BATS_TEST_TMPDIR/other.git"
  make_bare_repo "$other"
  seed_bare_repo "$other" "other seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git checkout -q -b one
  splice clone "$upstream" vendor/a >/dev/null 2>&1
  commit_local "$monorepo" vendor/a "unpushed in one" one.txt
  git checkout -q -b other main
  splice clone "$other" vendor/a >/dev/null 2>&1
  git checkout -q one
  git merge -q --no-commit -s ours other
  git rm -q -r vendor/a
  git checkout other -- vendor/a
  git commit -q -m "keep the other splice"
  [ "$(splice boundary vendor/a)" = "$(git rev-parse HEAD)" ]
  [ "$(splice rebuild vendor/a)" = "$(splice_config vendor/a commit)" ]
}

@test "rebuild: a splice swapped with a folder that wasn't one keeps its own history, not that folder's" {
  scenario_push_ahead "$monorepo" "$upstream"
  commit_local "$monorepo" internal "not for any upstream" secret.txt
  cd "$monorepo"
  local before
  before="$(splice rebuild vendor/a)"
  git mv internal tmp
  git mv vendor/a internal
  git mv tmp vendor/a
  git commit -q -m "swap internal and vendor/a"
  [ "$(splice rebuild internal)" = "$before" ]
}

@test "rebuild: a splice made by init, then swapped with another, keeps its own history, not the other's" {
  make_bare_repo "$BATS_TEST_TMPDIR/a.git"
  seed_bare_repo "$BATS_TEST_TMPDIR/a.git" "seed a"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$BATS_TEST_TMPDIR/a.git" vendor/a
  commit_local "$monorepo" vendor/a "not for b's upstream" a.txt
  commit_local "$monorepo" vendor/b "b before init" b.txt
  make_bare_repo "$BATS_TEST_TMPDIR/b.git"
  cd "$monorepo"
  splice init vendor/b "$BATS_TEST_TMPDIR/b.git"
  local b
  b="$(splice rebuild vendor/b)"
  [ "$(git log --format=%s "$b")" = "splice: init vendor/b" ]
  git mv vendor/a tmp
  git mv vendor/b vendor/a
  git mv tmp vendor/b
  git commit -q -m "swap a and b"
  [ "$(splice rebuild vendor/a)" = "$b" ]
}

@test "rebuild: a splice removed and cloned again doesn't get the history from its first time" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  splice init lib/a "$upstream"
  splice push lib/a
  commit_local "$monorepo" lib/a "unpushed, then removed" removed.txt
  git rm -q -r lib/a
  git commit -q -m "remove lib/a"
  add_splice "$monorepo" "$upstream" lib/a
  # Cloned with local changes, as clone --merge does.
  echo "merged" >lib/a/merged.txt
  git add lib/a/merged.txt
  git commit -q --amend -m "clone lib/a again"
  local rebuilt
  rebuilt="$(splice rebuild lib/a)"
  [ "$(git log --format=%s "$rebuilt")" = "clone lib/a again"$'\n'"splice: init lib/a" ]
}

@test "rebuild: a move with git mv keeps the unpushed commits from before it" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before_move
  before_move="$(splice rebuild vendor/a)"
  mkdir -p libs
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  # The move changes nothing upstream sees: the same commits as before it.
  [ "$(splice rebuild libs/a)" = "$before_move" ]
  [ "$(git log -1 --format=%s "$before_move")" = "local change" ]
}

@test "rebuild: a move on a feature branch, merged with a merge commit, keeps the unpushed commits from before it" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before_move
  before_move="$(splice rebuild vendor/a)"
  git switch -q -c reorganize
  mkdir -p libs
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  git switch -q main
  echo "meanwhile" >README.md
  git add README.md
  git commit -q -m "meanwhile on main"
  git merge -q --no-ff -m "merge reorganize" reorganize
  [ "$(splice rebuild libs/a)" = "$before_move" ]
}

@test "rebuild: changes on both sides of a feature branch that moved the folder become one commit for the merge, on top of the commits from before the move" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git switch -q -c reorganize
  commit_local "$monorepo" vendor/a "before the move on the branch" branch.txt
  mkdir -p libs
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  commit_local "$monorepo" libs/a "after the move on the branch" branch.txt
  git switch -q main
  commit_local "$monorepo" vendor/a "on main"
  git merge -q --no-ff -m "merge reorganize" reorganize
  local rebuilt
  rebuilt="$(splice rebuild libs/a)"
  [ "$(git log --format=%s "$rebuilt")" = $'merge reorganize\non main\nlocal change\nseed' ]
  [ "$(git rev-parse "$rebuilt:branch.txt")" = "$(git rev-parse HEAD:libs/a/branch.txt)" ]
  [ "$(git rev-parse "$rebuilt:file.txt")" = "$(git rev-parse HEAD:libs/a/file.txt)" ]
}

@test "rebuild: commits after a move, and a second move, keep the history" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p libs pkgs
  git mv vendor/a libs/a
  git commit -q -m "first move"
  commit_local "$monorepo" "libs/a" "between the moves"
  git mv libs/a pkgs/a
  echo "edited while moving" >>pkgs/a/file.txt
  git add pkgs/a
  git commit -q -m "second move, with an edit"
  commit_local "$monorepo" "pkgs/a" "after the moves"
  local rebuilt
  rebuilt="$(splice rebuild pkgs/a)"
  [ "$(git log --format=%s "$(splice_config pkgs/a commit)..$rebuilt")" = \
    "after the moves"$'\n'"second move, with an edit"$'\n'"between the moves"$'\n'"local change" ]
  content_tree HEAD pkgs/a
  [ "$(git rev-parse "$rebuilt^{tree}")" = "$CONTENT_TREE" ]
}

@test "rebuild: init on a folder moved earlier starts at init: the history from before isn't followed" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p libs
  git mv lib/a libs/a
  git commit -q -m "reorganize folders"
  commit_local "$monorepo" "libs/a" "third version"
  printf '[splice]\n\tid = 0123456789abcdef\n[upstream "origin"]\n\turl = %s\n' "$upstream" >libs/a/.splice
  git add libs/a/.splice
  git commit -q -m "init libs/a"
  commit_local "$monorepo" "libs/a" "fourth version"
  local rebuilt
  rebuilt="$(splice rebuild libs/a)"
  [ "$(git log --format=%s "$rebuilt")" = "fourth version"$'\n'"init libs/a" ]
}

@test "rebuild: a move that also rewrites .splice keeps the unpushed commits from before it" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before_move
  before_move="$(splice rebuild vendor/a)"
  mkdir -p libs
  git mv vendor/a libs/a
  # Too different for Git to detect .splice itself as renamed.
  git config --file libs/a/.splice --rename-section upstream.origin upstream.github
  git config --file libs/a/.splice upstream.github.url "https://github.com/example-organization/a-much-longer-repository-name.git"
  git add libs/a
  git commit -q -m "move, and publish somewhere else"
  [ "$(git log -1 --format=%s -- libs/a/.splice)" = "move, and publish somewhere else" ]
  [ "$(splice rebuild libs/a)" = "$before_move" ]
}

@test "rebuild: a move that also deletes, renames and adds files keeps the unpushed commits from before it" {
  scenario_push_ahead "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "add notes" notes.txt
  commit_local "$monorepo" vendor/a "add todo" todo.txt
  cd "$monorepo"
  mkdir -p libs
  git mv vendor/a libs/a
  git rm -qf libs/a/notes.txt
  git mv libs/a/todo.txt libs/a/TODO.txt
  echo "new" >libs/a/new.txt
  git add libs/a
  git commit -q -m "reorganize folders, and tidy up"
  local rebuilt
  rebuilt="$(splice rebuild libs/a)"
  [ "$(git log --format=%s "$(splice_config libs/a commit)..$rebuilt")" = \
    "reorganize folders, and tidy up"$'\n'"add todo"$'\n'"add notes"$'\n'"local change" ]
  content_tree HEAD libs/a
  [ "$(git rev-parse "$rebuilt^{tree}")" = "$CONTENT_TREE" ]
}

@test "rebuild: follows a move of a folder whose name has non-ASCII characters" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/ä"
  commit_local "$monorepo" "vendor/ä" "local change"
  cd "$monorepo"
  local before_move
  before_move="$(splice rebuild "vendor/ä")"
  mkdir -p libs
  git mv "vendor/ä" "libs/ä"
  git commit -q -m "reorganize folders"
  [ "$(splice rebuild "libs/ä")" = "$before_move" ]
}

@test "rebuild: two splices with the same .splice, moved in one commit, each keep their own commits" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  # A plain copy: the same id, and the same synced commit.
  cp "$monorepo/vendor/a/.splice" "$monorepo/vendor/b/.splice"
  git -C "$monorepo" commit -q -am "vendor/b: a copy of vendor/a's .splice"
  commit_local "$monorepo" vendor/a "change in a" a.txt
  commit_local "$monorepo" vendor/b "change in b" b.txt
  cd "$monorepo"
  [ "$(git rev-parse HEAD:vendor/a/.splice)" = "$(git rev-parse HEAD:vendor/b/.splice)" ]
  local a b
  a="$(splice rebuild vendor/a)"
  b="$(splice rebuild vendor/b)"
  mkdir -p libs
  git mv vendor/a libs/y
  git mv vendor/b libs/x
  git commit -q -m "reorganize folders"
  [ "$(splice rebuild libs/x)" = "$b" ]
  [ "$(splice rebuild libs/y)" = "$a" ]
}

@test "rebuild: init on a folder that one file was moved into doesn't publish the folder it came from" {
  init_monorepo "$monorepo"
  make_bare_repo "$upstream"
  commit_local "$monorepo" internal "public" file.txt
  commit_local "$monorepo" internal "not for the upstream" secret.txt
  cd "$monorepo"
  mkdir -p libs/x
  git mv internal/file.txt libs/x/file.txt
  git commit -q -m "extract file.txt"
  printf '[splice]\n\tid = 0123456789abcdef\n[upstream "origin"]\n\turl = %s\n' "$upstream" >libs/x/.splice
  git add libs/x/.splice
  git commit -q -m "init libs/x"
  local rebuilt
  rebuilt="$(splice rebuild libs/x)"
  [ "$(git log --format=%s "$rebuilt")" = "init libs/x" ]
  [ "$(git ls-tree --name-only "$rebuilt")" = "file.txt" ]
}

@test "rebuild: without the synced commit, push --force follows moves from before the boundary" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p libs
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  git config --file libs/a/.splice splice.commit 1111111111111111111111111111111111111111
  git commit -q -am "a pull of a commit the upstream no longer has"
  splice push --force libs/a >/dev/null
  [ "$(git -C "$upstream" log --format=%s main)" = "local change"$'\n'"add vendor/a" ]
}

@test "rebuild: without a synced commit, a move that also rewrites .splice keeps the history since init: the id is the same" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  splice init lib/a "$upstream"
  commit_local "$monorepo" "lib/a" "third version"
  mkdir -p libs
  git mv lib/a libs/a
  git config --file libs/a/.splice --rename-section upstream.origin upstream.github
  git config --file libs/a/.splice upstream.github.url "https://github.com/example-organization/a-much-longer-repository-name.git"
  git add libs/a
  git commit -q -m "move, and publish somewhere else"
  local rebuilt
  rebuilt="$(splice rebuild libs/a)"
  [ "$(git log --format=%s "$rebuilt")" = "third version"$'\n'"splice: init lib/a" ]
}

@test "rebuild: a move keeps the unpushed commits even if a new folder takes the old path in the same commit" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(splice rebuild vendor/a)"
  mkdir -p libs
  git mv vendor/a libs/a
  mkdir vendor/a
  echo "new" >vendor/a/new.txt
  git add vendor/a
  git commit -q -m "move, and a new vendor/a"
  [ "$(splice rebuild libs/a)" = "$before" ]
}

@test "rebuild: mirrors with the same files, moved in one commit, each follow the folder with its own name" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  cp -r vendor/a vendor/b
  git add vendor/b
  git commit -q -m "mirror a as b"
  commit_local "$monorepo" vendor/a "in both" both.txt
  commit_local "$monorepo" vendor/b "in both" both.txt
  local a b
  a="$(splice rebuild vendor/a)"
  b="$(splice rebuild vendor/b)"
  [ "$a" != "$b" ]
  mkdir -p libs
  git mv vendor/a libs/a
  git mv vendor/b libs/b
  git commit -q -m "move both mirrors"
  [ "$(splice rebuild libs/a)" = "$a" ]
  [ "$(splice rebuild libs/b)" = "$b" ]
}

@test "rebuild: mirrors with the same files, moved in one commit to other names, are no move: nothing tells them apart" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  cp -r vendor/a vendor/b
  git add vendor/b
  git commit -q -m "mirror a as b"
  mkdir -p libs
  git mv vendor/a libs/x
  git mv vendor/b libs/y
  git commit -q -m "move both mirrors"
  [ "$(splice boundary libs/x)" = "$(git rev-parse HEAD)" ]
}

@test "rebuild: a move while another splice with the same files is deleted follows the moved one, by its id" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "the same change" x.txt
  commit_local "$monorepo" vendor/b "the same change" x.txt
  cd "$monorepo"
  [ "$(git rev-parse HEAD:vendor/a/x.txt)" = "$(git rev-parse HEAD:vendor/b/x.txt)" ]
  local before
  before="$(splice rebuild vendor/a)"
  mkdir -p libs
  git mv vendor/a libs/a
  git rm -q -r vendor/b
  git commit -q -m "move a, remove b"
  [ "$(splice rebuild libs/a)" = "$before" ]
}

@test "rebuild: a move that rewrites every file follows the splice, not a deleted folder that shares a file with it" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir internal
  echo "rewritten" >internal/file.txt
  git add internal
  git commit -q -m "internal"
  local before
  before="$(splice rebuild vendor/a)"
  mkdir -p libs
  git mv vendor/a libs/a
  echo "rewritten" >libs/a/file.txt
  git rm -q -r internal
  git add libs/a
  git commit -q -m "move, and rewrite"
  local rebuilt
  rebuilt="$(splice rebuild libs/a)"
  [ "$(git rev-parse "$rebuilt^")" = "$before" ]
  [ "$(git log -1 --format=%s "$rebuilt")" = "move, and rewrite" ]
}

@test "rebuild: a move that changes .splice and undoes the unpushed changes keeps their commits" {
  scenario_up_to_date "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "added" extra.txt
  cd "$monorepo"
  mkdir -p libs
  git mv vendor/a libs/a
  git rm -q -f libs/a/extra.txt
  git config --file libs/a/.splice upstream.origin.default-branch main
  git add libs/a
  git commit -q -m "move, and undo"
  [ "$(git rev-parse HEAD:libs/a/file.txt)" = "$(git rev-parse "$(splice_config libs/a commit):file.txt")" ]
  [ "$(git log --format=%s "$(splice rebuild libs/a)")" = "move, and undo"$'\n'"added"$'\n'"seed" ]
}

@test "rebuild: log.showSignature doesn't hide a signed move" {
  command -v ssh-keygen >/dev/null || skip "no ssh-keygen to sign a commit with"
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  ssh-keygen -q -t ed25519 -N "" -f "$BATS_TEST_TMPDIR/key"
  git config gpg.format ssh
  git config user.signingKey "$BATS_TEST_TMPDIR/key.pub"
  local before
  before="$(splice rebuild vendor/a)"
  mkdir -p libs
  git mv vendor/a libs/a
  git commit -q -S -m "a signed move"
  git config log.showSignature true
  [ "$(splice rebuild libs/a)" = "$before" ]
}

@test "rebuild: a moved splice without local changes stays at its synced commit" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p libs
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  [ "$(splice rebuild libs/a)" = "$(splice_config libs/a commit)" ]
}

@test "rebuild: a synced commit that isn't available locally is an error" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice splice.commit 1234567890123456789012345678901234567890
  git commit -q -am "point at a missing commit"
  run splice rebuild vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"synced commit 1234567 isn't available locally"* ]]
}

@test "rebuild: a commit that only changes .splice adds nothing upstream" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(splice rebuild vendor/a)"
  git config --file vendor/a/.splice upstream.origin.default-branch main
  git commit -q -am "name the default branch"
  [ "$(splice rebuild vendor/a)" = "$before" ]
}

@test "rebuild: a new upstream URL keeps the splice's history: its id is the same" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(splice rebuild vendor/a)"
  git config --file vendor/a/.splice upstream.origin.url "$upstream/../moved.git"
  git commit -q -am "the upstream moved"
  [ "$(splice rebuild vendor/a)" = "$before" ]
}

@test "rebuild: a commit that only changes .splice after a push leaves the state up to date" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  splice push vendor/a >/dev/null 2>&1
  git config --file vendor/a/.splice upstream.origin.default-branch main
  git commit -q -am "record the default branch"
  [ "$(splice_state vendor/a)" = up-to-date ]
}

@test "rebuild command: prints the commit push sends" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run splice rebuild vendor/a
  [ "$status" -eq 0 ]
  local rebuilt="$output"
  [ "$(git log -1 --format=%s "$rebuilt")" = "local change" ]
  splice push vendor/a >/dev/null
  [ "$(git ls-remote "$upstream" refs/heads/main | cut -f1)" = "$rebuilt" ]
}

@test "rebuild command: writes nothing, neither a ref nor a monorepo commit" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local refs
  refs="$(git for-each-ref)"
  splice rebuild vendor/a >/dev/null
  [ "$(git for-each-ref)" = "$refs" ]
  [ -z "$(git status --porcelain)" ]
}

@test "rebuild command: is the synced commit when nothing changed locally" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  run splice rebuild vendor/a
  [ "$output" = "$(splice_config vendor/a commit)" ]
}

@test "rebuild command: works on a detached HEAD, which syncs with no upstream branch but still has a rebuild" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local expected
  expected="$(splice rebuild vendor/a)"
  git checkout -q --detach
  run splice rebuild vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "rebuild command: takes exactly one splice" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  cd "$monorepo"
  run splice rebuild
  [ "$status" -eq 1 ]
  [[ "$output" == *$'SYNOPSIS\n    git splice rebuild <path>'* ]]
  run splice rebuild vendor/a vendor/b
  [ "$status" -eq 1 ]
  [[ "$output" == *$'SYNOPSIS\n    git splice rebuild <path>'* ]]
  run splice rebuild --all
  [ "$output" = "!!   rebuild takes no --all" ]
  run splice rebuild vendor
  [ "$output" = "!!   not a splice: vendor" ]
}

@test "rebuild command: a synced commit that isn't available locally is an error, and prints no commit" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice splice.commit 1234567890123456789012345678901234567890
  git commit -q -am "point at a missing commit"
  run splice rebuild vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == "!!   vendor/a: synced commit 1234567 isn't available locally"* ]]
  stdout_only() { splice rebuild vendor/a 2>/dev/null; }
  run stdout_only
  [ -z "$output" ]
}

@test "rebuild command: a synced commit from before a move that isn't available locally names the splice's path now" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local synced
  synced="$(splice_config vendor/a commit)"
  git config --file vendor/a/.splice splice.commit 1234567890123456789012345678901234567890
  git commit -q -am "point at a missing commit"
  mkdir libs
  git mv vendor/a libs/a
  git config --file libs/a/.splice splice.commit "$synced"
  git commit -q -am "move and point back"
  run splice rebuild libs/a
  [ "$status" -eq 1 ]
  [[ "$output" == "!!   libs/a: synced commit 1234567 isn't available locally -- run 'git splice fetch libs/a'"* ]]
}

# From scenario_patch_branch_rebased: a pull request's branch pulls the
# rebased patch branch, adds local change $1 (nothing: none), and is
# squash-merged into main.
squash_merge_rebased_pull() {
  cd "$monorepo"
  git switch -q -c take-the-release
  (splice merge --branch patches vendor/a) >/dev/null
  [[ -z "${1:-}" ]] || commit_local "$monorepo" vendor/a "$1" local.txt
  git switch -q main
  git merge -q --squash take-the-release >/dev/null
  git commit -q -m "take the release (#1)"
}

@test "rebuild: refuses a squash merge that mixes a local change into a pull of a rewritten upstream branch" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  local previous
  previous="$(git -C "$monorepo" config --file vendor/a/.splice splice.commit)"
  squash_merge_rebased_pull "local change"
  local synced
  synced="$(splice_config vendor/a commit)"
  run splice rebuild vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   vendor/a: $(git rev-parse --short=7 HEAD) records ${synced:0:7}, which the upstream rewrote from ${previous:0:7}, and has changes of its own -- commit the folder's changes on top of the upstream branch yourself, push them there, then pull: the rebuild would publish the rewritten-away commits again" ]
}

@test "rebuild: refuses that squash merge also where it moves the folder" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  local previous
  previous="$(git -C "$monorepo" config --file vendor/a/.splice splice.commit)"
  cd "$monorepo"
  git switch -q -c take-the-release
  (splice merge --branch patches vendor/a) >/dev/null
  commit_local "$monorepo" vendor/a "local change" local.txt
  mkdir libs
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  git switch -q main
  git merge -q --squash take-the-release >/dev/null
  git commit -q -m "take the release (#1)"
  local synced
  synced="$(splice_config libs/a commit)"
  run splice rebuild libs/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   libs/a: $(git rev-parse --short=7 HEAD) records ${synced:0:7}, which the upstream rewrote from ${previous:0:7}, and has changes of its own -- commit the folder's changes on top of the upstream branch yourself, push them there, then pull: the rebuild would publish the rewritten-away commits again" ]
}

@test "rebuild: refuses that squash merge also after a later move that changed .splice, naming the splice's path now" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  local previous
  previous="$(git -C "$monorepo" config --file vendor/a/.splice splice.commit)"
  squash_merge_rebased_pull "local change"
  local squash synced
  squash="$(git rev-parse --short=7 HEAD)"
  synced="$(splice_config vendor/a commit)"
  mkdir libs
  git mv vendor/a libs/a
  printf '# moved\n' >>libs/a/.splice
  git add libs/a/.splice
  git commit -q -m "reorganize folders"
  run splice rebuild libs/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   libs/a: $squash records ${synced:0:7}, which the upstream rewrote from ${previous:0:7}, and has changes of its own -- commit the folder's changes on top of the upstream branch yourself, push them there, then pull: the rebuild would publish the rewritten-away commits again" ]
}

@test "rebuild: without the fetched branch's reflog, e.g. in a clone that fetched only after the rewrite, the squash merge is joined and keeps the rewritten-away commits, as git merge would" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  local previous
  previous="$(git -C "$monorepo" config --file vendor/a/.splice splice.commit)"
  squash_merge_rebased_pull "local change"
  git reflog expire --expire=all --all
  run splice rebuild vendor/a
  [ "$status" -eq 0 ]
  git merge-base --is-ancestor "$previous" "$output"
}

@test "rebuild: another splice's upstream that still has the synced commit before doesn't make the squash merge a join" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  local previous other="$BATS_TEST_TMPDIR/other.git"
  previous="$(git -C "$monorepo" config --file vendor/a/.splice splice.commit)"
  git clone -q --bare "$upstream" "$other"
  git -C "$other" update-ref refs/heads/keep "$previous"
  add_splice "$monorepo" "$other" vendor/other keep
  squash_merge_rebased_pull "local change"
  run splice rebuild vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == "!!   vendor/a: "*" which the upstream rewrote from ${previous:0:7}, "* ]]
}

@test "rebuild: a squash merge that moves to another upstream branch is joined, though the branch it left was rewritten: that branch didn't give the new synced commit" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  local previous
  previous="$(git -C "$monorepo" config --file vendor/a/.splice splice.commit)"
  git -C "$upstream" branch release main~1
  seed_bare_repo "$upstream" "release" release release.txt
  fetch_splice "$monorepo" "$upstream" vendor/a
  cd "$monorepo"
  git switch -q -c take-the-release
  (splice merge --branch release vendor/a) >/dev/null
  commit_local "$monorepo" vendor/a "local change" local.txt
  git switch -q main
  git merge -q --squash take-the-release >/dev/null
  git commit -q -m "take the release (#1)"
  run splice rebuild vendor/a
  [ "$status" -eq 0 ]
}

@test "rebuild: a squash merge of only the pull of a rewritten upstream branch starts at that branch" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  squash_merge_rebased_pull
  [ "$(splice rebuild vendor/a)" = "$(git rev-parse "$(upstream_refs "$upstream")patches")" ]
}

@test "rebuild: after the refused squash merge, pushing its change upstream by hand and pulling makes the rebuild that branch" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  squash_merge_rebased_pull "local change"
  local fork="$BATS_TEST_TMPDIR/fork"
  git clone -q -b patches "$upstream" "$fork"
  cp vendor/a/local.txt "$fork/"
  git -C "$fork" add local.txt
  git -C "$fork" -c user.name=Test -c user.email=test@example.com commit -q -m "local change"
  git -C "$fork" push -q origin HEAD:patches
  fetch_splice "$monorepo" "$upstream" vendor/a
  (splice merge vendor/a) >/dev/null
  [ "$(splice rebuild vendor/a)" = "$(git rev-parse "$(upstream_refs "$upstream")patches")" ]
}

@test "rebuild: a commit the rebuild can't write fails status, push and log, instead of reading as unrelated history" {
  scenario_push_ahead "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "another change" another.txt
  cd "$monorepo"
  # As on a full disk: git can't add the rebuild's new objects.
  find .git/objects -type d -exec chmod a-w {} +
  local status_status status_output push_status push_output log_status log_output
  run splice status
  status_status="$status" status_output="$output"
  run splice push vendor/a
  push_status="$status" push_output="$output"
  run splice log vendor/a
  log_status="$status" log_output="$output"
  run splice rebuild vendor/a
  find .git/objects -type d -exec chmod u+w {} +
  [ "$status_status" -eq 1 ]
  [[ "$status_output" != *"unrelated history"* ]]
  [ "$push_status" -eq 1 ]
  [[ "$push_output" != *"pick a side"* ]]
  [ "$log_status" -eq 1 ]
  [[ "$log_output" != *"share no history"* ]]
  [ "$status" -eq 1 ]
  [[ "$output" != *"has no content yet"* ]]
  [[ "$output" == *"insufficient permission"* ]]
}
