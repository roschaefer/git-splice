# The push rebuild, checked against `git subtree split` as the test oracle:
# where both apply, the rebuild must make byte-identical commits. Where it
# deliberately differs, the test says so and asserts exactly how ("approved
# divergence"). See docs/design/README.md.

setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/up-to-date/push-ahead/setup'
  load 'scenarios/up-to-date/diverged-then-pulled/setup'
  load 'scenarios/up-to-date/squash-merged-pull/setup'
  load 'scenarios/init-new-upstream/setup'
  load 'scenarios/up-to-date/setup'
  load 'scenarios/up-to-date/shared-remote-url/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

# A monorepo whose vendor/a was added by `git subtree add --squash`, which
# split understands. Sets B (the add's merge, i.e. the boundary) and U (the
# upstream commit it added). No .splice: split would put it in every tree.
oracle_fixture() {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git subtree add -q --prefix=vendor/a "$upstream" main --squash >/dev/null 2>&1
  B="$(git rev-parse HEAD)"
  U="$(git ls-remote "$upstream" refs/heads/main | cut -f1)"
}

split() {
  git -c commit.gpgSign=false subtree split -q --prefix=vendor/a HEAD 2>/dev/null
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
  rebuilt="$(rebuild_walk vendor/a "$U" "$B..HEAD")"
  [ "$(git rev-list --count "$U..$rebuilt")" -eq 3 ]
  [ "$rebuilt" = "$(split)" ]
}

@test "rebuild: approved divergence: a merge in the monorepo becomes one ordinary commit" {
  oracle_fixture
  git checkout -q -b feature
  commit_local "$monorepo" "vendor/a" "feature work" feature.txt
  local before_merge
  before_merge="$(rebuild_walk vendor/a "$U" "$B..HEAD")"
  git checkout -q main
  commit_local "$monorepo" "vendor/a" "main work" main.txt
  git checkout -q feature
  git merge -q --no-edit main
  commit_local "$monorepo" "vendor/a" "after the merge" feature.txt

  local ours theirs
  ours="$(rebuild_walk vendor/a "$U" "$B..HEAD")"
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
  rebuilt="$(rebuild_splice vendor/a)"
  # The only difference to the monorepo's folder is the state file.
  [ "$(git diff --name-only "$rebuilt" HEAD:vendor/a)" = ".splice" ]
  [ "$(git ls-tree --name-only -z "$rebuilt" | tr -cd '\0' | wc -c)" -eq 5 ]
}

@test "rebuild: is deterministic, even when commits would be signed" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config commit.gpgSign true
  local first
  first="$(rebuild_splice vendor/a)"
  [ -n "$first" ]
  [ "$(rebuild_splice vendor/a)" = "$first" ]
}

@test "rebuild: starts at the synced commit and leaves .splice out" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a)"
  [ "$(git rev-parse "$rebuilt^")" = "$(splice_config vendor/a commit)" ]
  [ "$(git log -1 --format=%s "$rebuilt")" = "local change" ]
  ! git cat-file -e "$rebuilt:.splice" 2>/dev/null
}

@test "rebuild: is the synced commit itself when nothing changed locally" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  [ "$(rebuild_splice vendor/a HEAD^)" = "$(splice_config vendor/a commit)" ]
}

@test "rebuild: after init, the history starts at the init commit: earlier commits aren't published" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  printf '[splice]\n\tid = 0123456789abcdef\n[upstream "origin"]\n\turl = %s\n' "$upstream" >lib/a/.splice
  git add lib/a/.splice
  git commit -q -m "init lib/a"
  commit_local "$monorepo" lib/a "third version"
  local rebuilt
  rebuilt="$(rebuild_splice lib/a)"
  [ "$(git log --format=%s "$rebuilt")" = "third version"$'\n'"init lib/a" ]
  content_tree "HEAD~1" lib/a
  [ "$(git rev-parse "$rebuilt~1^{tree}")" = "$CONTENT_TREE" ]
  [ -z "$(git rev-parse "$rebuilt~1^@")" ]
}

@test "rebuild: a pull that merged a divergence keeps the unpushed commit and joins upstream with a merge" {
  scenario_diverged_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt synced
  rebuilt="$(rebuild_splice vendor/a)"
  synced="$(splice_config vendor/a commit)"
  [ "$(git rev-parse "$rebuilt^2")" = "$synced" ]
  [ "$(git log -1 --format=%s "$rebuilt^1")" = "local change" ]
  [ "$(git rev-parse "$rebuilt^1^")" = "$(git rev-parse "$synced^")" ]
}

@test "rebuild: approved divergence: a squash-merged pull doesn't repeat upstream's commit" {
  scenario_squash_merged_pull "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt feature_tip
  rebuilt="$(rebuild_splice vendor/a)"
  feature_tip="$(git rev-parse "$(upstream_refs "$upstream")feature")"
  # The squash merge is the boundary: the rebuild starts at the pulled
  # upstream commit itself, then only the local change follows.
  [ "$(git rev-parse "$rebuilt^")" = "$feature_tip" ]
  [ "$(git log -1 --format=%s "$rebuilt")" = "local change" ]
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
  rebuilt="$(rebuild_splice vendor/a)"
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

@test "rebuild: two splices that swap paths don't get each other's history" {
  two_splices_ahead
  cd "$monorepo"
  git mv vendor/a tmp
  git mv vendor/b vendor/a
  git mv tmp vendor/b
  git commit -q -m "swap a and b"
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a)"
  # b's unpushed commit is folded into the swap: the rebuild doesn't
  # follow moves yet (#4). But nothing of a's reaches b's upstream.
  [ "$(git log --format=%s "$rebuilt")" = "swap a and b"$'\n'"seed b" ]
  content_tree HEAD vendor/a
  [ "$(git rev-parse "$rebuilt^{tree}")" = "$CONTENT_TREE" ]
}

@test "rebuild: two splices of the same upstream that swap paths don't get each other's history" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "unpushed in a" a.txt
  commit_local "$monorepo" vendor/b "unpushed in b" b.txt
  cd "$monorepo"
  git mv vendor/a tmp
  git mv vendor/b vendor/a
  git mv tmp vendor/b
  git commit -q -m "swap a and b"
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a)"
  [ "$(git log --format=%s "$rebuilt")" = "swap a and b"$'\n'"seed" ]
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
  cmd_clone "$upstream" vendor/a >/dev/null 2>&1
  commit_local "$monorepo" vendor/a "unpushed in one" one.txt
  git checkout -q -b other main
  cmd_clone "$other" vendor/a >/dev/null 2>&1
  git checkout -q one
  git merge -q --no-commit -s ours other
  git rm -q -r vendor/a
  git checkout other -- vendor/a
  git commit -q -m "keep the other splice"
  [ "$(splice_mount vendor/a)" = "$(git rev-parse HEAD)" ]
  [ "$(rebuild_splice vendor/a)" = "$(splice_config vendor/a commit)" ]
}

@test "rebuild: a .splice from before ids is another splice, so the commit that gives it an id is the mount, and unpushed changes are folded into it" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local id
  id="$(splice_config vendor/a id)"
  git config --file vendor/a/.splice --unset splice.id
  git commit -q -am "a splice from before ids"
  git config --file vendor/a/.splice splice.id "$id"
  git commit -q -am "give vendor/a an id"
  [ "$(splice_mount vendor/a)" = "$(git rev-parse HEAD)" ]
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a)"
  [ "$(git log --format=%s "$rebuilt")" = "give vendor/a an id"$'\n'"seed" ]
  content_tree HEAD vendor/a
  [ "$(git rev-parse "$rebuilt^{tree}")" = "$CONTENT_TREE" ]
}

@test "rebuild: a splice moved onto a folder that wasn't one doesn't get that folder's history" {
  scenario_push_ahead "$monorepo" "$upstream"
  commit_local "$monorepo" internal "not for any upstream" secret.txt
  cd "$monorepo"
  git mv internal tmp
  git mv vendor/a internal
  git mv tmp vendor/a
  git commit -q -m "swap internal and vendor/a"
  local rebuilt
  rebuilt="$(rebuild_splice internal)"
  [ "$(git log --format=%s "$rebuilt")" = "swap internal and vendor/a"$'\n'"seed" ]
}

@test "rebuild: a splice made by init, then swapped with another, doesn't get the other's history" {
  make_bare_repo "$BATS_TEST_TMPDIR/a.git"
  seed_bare_repo "$BATS_TEST_TMPDIR/a.git" "seed a"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$BATS_TEST_TMPDIR/a.git" vendor/a
  commit_local "$monorepo" vendor/a "not for b's upstream" a.txt
  commit_local "$monorepo" vendor/b "b before init" b.txt
  make_bare_repo "$BATS_TEST_TMPDIR/b.git"
  cd "$monorepo"
  cmd_init vendor/b "$BATS_TEST_TMPDIR/b.git"
  git mv vendor/a tmp
  git mv vendor/b vendor/a
  git mv tmp vendor/b
  git commit -q -m "swap a and b"
  local rebuilt
  rebuilt="$(rebuild_splice vendor/a)"
  [ "$(git log --format=%s "$rebuilt")" = "swap a and b" ]
  content_tree HEAD vendor/a
  [ "$(git rev-parse "$rebuilt^{tree}")" = "$CONTENT_TREE" ]
}

@test "rebuild: a splice removed and cloned again doesn't get the history from its first time" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_init lib/a "$upstream"
  cmd_push lib/a
  commit_local "$monorepo" lib/a "unpushed, then removed" removed.txt
  git rm -q -r lib/a
  git commit -q -m "remove lib/a"
  add_splice "$monorepo" "$upstream" lib/a
  # Cloned with local changes, as clone --merge does.
  echo "merged" >lib/a/merged.txt
  git add lib/a/merged.txt
  git commit -q --amend -m "clone lib/a again"
  local rebuilt
  rebuilt="$(rebuild_splice lib/a)"
  [ "$(git log --format=%s "$rebuilt")" = "clone lib/a again"$'\n'"splice: init lib/a" ]
}

@test "rebuild: a move with git mv keeps the unpushed commits from before it" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before_move
  before_move="$(rebuild_splice vendor/a)"
  mkdir -p libs
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  # The move changes nothing upstream sees: the same commits as before it.
  [ "$(rebuild_splice libs/a)" = "$before_move" ]
  [ "$(git log -1 --format=%s "$before_move")" = "local change" ]
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
  rebuilt="$(rebuild_splice pkgs/a)"
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
  rebuilt="$(rebuild_splice libs/a)"
  [ "$(git log --format=%s "$rebuilt")" = "fourth version"$'\n'"init libs/a" ]
}

@test "rebuild: a move that also rewrites .splice keeps the unpushed commits from before it" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before_move
  before_move="$(rebuild_splice vendor/a)"
  mkdir -p libs
  git mv vendor/a libs/a
  # Too different for Git to detect .splice itself as renamed.
  git config --file libs/a/.splice --rename-section upstream.origin upstream.github
  git config --file libs/a/.splice upstream.github.url "https://github.com/example-organization/a-much-longer-repository-name.git"
  git add libs/a
  git commit -q -m "move, and publish somewhere else"
  [ "$(git log -1 --format=%s -- libs/a/.splice)" = "move, and publish somewhere else" ]
  [ "$(rebuild_splice libs/a)" = "$before_move" ]
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
  rebuilt="$(rebuild_splice libs/a)"
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
  before_move="$(rebuild_splice "vendor/ä")"
  mkdir -p libs
  git mv "vendor/ä" "libs/ä"
  git commit -q -m "reorganize folders"
  [ "$(rebuild_splice "libs/ä")" = "$before_move" ]
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
  a="$(rebuild_splice vendor/a)"
  b="$(rebuild_splice vendor/b)"
  mkdir -p libs
  git mv vendor/a libs/y
  git mv vendor/b libs/x
  git commit -q -m "reorganize folders"
  [ "$(rebuild_splice libs/x)" = "$b" ]
  [ "$(rebuild_splice libs/y)" = "$a" ]
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
  rebuilt="$(rebuild_splice libs/x)"
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
  local rebuilt
  rebuilt="$(REBUILD_WITHOUT_SYNCED=1 rebuild_splice libs/a)"
  [ "$(git log --format=%s "$rebuilt")" = "local change"$'\n'"add vendor/a" ]
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
  rebuilt="$(rebuild_splice libs/a)"
  [ "$(git log --format=%s "$rebuilt")" = "third version"$'\n'"splice: init lib/a" ]
}

@test "rebuild: a moved splice without local changes stays at its synced commit" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  mkdir -p libs
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  [ "$(rebuild_splice libs/a)" = "$(splice_config libs/a commit)" ]
}

@test "rebuild: a synced commit that isn't available locally is an error" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config --file vendor/a/.splice splice.commit 1234567890123456789012345678901234567890
  git commit -q -am "point at a missing commit"
  run rebuild_splice vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"synced commit 1234567 isn't available locally"* ]]
}

@test "rebuild: a commit that only changes .splice adds nothing upstream" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(rebuild_splice vendor/a)"
  git config --file vendor/a/.splice splice.default-branch main
  git commit -q -am "name the default branch"
  [ "$(rebuild_splice vendor/a)" = "$before" ]
}

@test "rebuild: a new upstream URL keeps the splice's history: its id is the same" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(rebuild_splice vendor/a)"
  git config --file vendor/a/.splice upstream.origin.url "$upstream/../moved.git"
  git commit -q -am "the upstream moved"
  [ "$(rebuild_splice vendor/a)" = "$before" ]
}

@test "rebuild: a commit that only changes .splice after a push leaves the state up to date" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  splice push vendor/a >/dev/null 2>&1
  git config --file vendor/a/.splice splice.default-branch main
  git commit -q -am "record the default branch"
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = up-to-date ]
}
