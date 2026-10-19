setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  load 'scenarios/01-everyday-sync/02-up-to-date/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/01-pull-ahead/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/03-diverged-common-ancestor/setup'
  load 'scenarios/06-rewritten-history/03-diverged-unrelated-history/setup'
  load 'scenarios/01-everyday-sync/04-never-fetched/setup'
  load 'scenarios/04-upstreams/03-shared-remote-url/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/01-pushed-then-pulled/setup'
  load 'scenarios/01-everyday-sync/02-up-to-date/02-push-ahead/01-pushed-then-pulled/01-pushed-then-changed/setup'
  load 'scenarios/02-starting-a-splice/04-init-new-upstream/setup'
  load 'scenarios/06-rewritten-history/01-edited-before-push/setup'
  load 'scenarios/06-rewritten-history/02-upstream-rewritten-equal-tree/setup'
  load 'scenarios/06-rewritten-history/04-patch-branch-rebased/01-unpushed-local-commit/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "merge: adds exactly one first-parent commit and no upstream ancestors" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD^)" = "$before" ]
  [ "$(git rev-list --parents -1 HEAD | wc -w)" -eq 2 ]
  ! git merge-base --is-ancestor "$(upstream_refs "$upstream")main" HEAD
  [ "$(git log -1 --format=%s)" = "splice: merge vendor/a from main at $(git rev-parse --short=7 "$(upstream_refs "$upstream")main")" ]
}

@test "merge: refuses an upstream that added a submodule" {
  scenario_pull_ahead "$monorepo" "$upstream"
  local inner="$BATS_TEST_TMPDIR/inner.git"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "inner"
  add_upstream_submodule "$upstream" "$inner" libs/inner
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run cmd_pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: upstream has a submodule, libs/inner, which nobody could check out"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge: brings upstream's content and records the synced commit" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_merge vendor/a
  [ "$(git rev-parse HEAD:vendor/a/file.txt)" = "$(git rev-parse "$(upstream_refs "$upstream")main":file.txt)" ]
  [ "$(splice_config vendor/a commit)" = "$(git rev-parse "$(upstream_refs "$upstream")main")" ]
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = up-to-date ]
}

@test "merge: keeps the splice's id" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local id
  id="$(splice_config vendor/a id)"
  cmd_merge vendor/a
  [ "$(splice_config vendor/a id)" = "$id" ]
}

@test "merge: refuses an upstream that brings in a .splice at its root" {
  scenario_pull_ahead "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "[splice]" main .splice
  cd "$monorepo"
  splice fetch vendor/a >/dev/null
  local before
  before="$(git rev-parse HEAD)"
  run cmd_merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"upstream has a .splice at its root, which would replace vendor/a/.splice"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge: keeps local changes when merging a divergence" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  # Make the two changes touch different files, so they merge cleanly.
  git reset -q --hard HEAD^
  commit_local "$monorepo" "vendor/a" "local change" local.txt
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/local.txt)" = "local change" ]
  grep -q "upstream change" vendor/a/file.txt
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = push ]
}

@test "merge: a conflict is resolved like any other, and git commit finishes it" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT"*"vendor/a/file.txt"* ]]
  [[ "$output" == *"resolve it, then 'git commit'"* ]]
  [ "$(git status --porcelain vendor/a/file.txt)" = "UU vendor/a/file.txt" ]
  printf 'seed\nboth\n' >vendor/a/file.txt
  git add vendor/a/file.txt
  git commit -q --no-edit
  [[ "$(git log -1 --format=%s)" == "splice: merge vendor/a from main at "* ]]
  [ "$(splice_config vendor/a commit)" = "$(git rev-parse "$(upstream_refs "$upstream")main")" ]
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = push ]
}

@test "merge: stops at a conflict and doesn't start the next splice" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  add_splice "$monorepo" "$upstream" vendor/b
  cd "$monorepo"
  run cmd_merge --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not merged yet: vendor/b"* ]]
}

@test "merge: nothing to do when up to date or only ahead" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to merge"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge: an upstream rewritten to the same files becomes the synced commit, so a later change pushes on top of it" {
  scenario_upstream_rewritten_equal_tree "$monorepo" "$upstream"
  cd "$monorepo"
  local before target
  before="$(git rev-parse HEAD)"
  target="$(git rev-parse "$(upstream_refs "$upstream")main")"
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD^)" = "$before" ]
  [ "$(git diff --name-only HEAD^ HEAD)" = "vendor/a/.splice" ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
  commit_local "$monorepo" vendor/a "local change"
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = push ]
  [ "$(git rev-parse "$SPLICE_REBUILT^")" = "$target" ]
}

@test "merge: a rebased upstream branch merges from its fork point, where the branch was before the rebase, so its dropped patch doesn't conflict" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  cd "$monorepo"
  local target
  target="$(git rev-parse "$(upstream_refs "$upstream")patches")"
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: merged ${target:0:7}" ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
  [ "$(git rev-parse HEAD:vendor/a/file.txt)" = "$(git rev-parse "$target:file.txt")" ]
  [ "$(rebuild_splice vendor/a)" = "$target" ]
}

@test "merge: a rebased upstream branch is refused while the folder has changes it lacks, which the next push would publish on the dropped patch" {
  scenario_unpushed_local_commit "$monorepo" "$upstream"
  cd "$monorepo"
  local before synced
  before="$(git rev-parse HEAD)"
  synced="$(splice_config vendor/a commit)"
  run cmd_merge vendor/a
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   vendor/a: upstream rewrote 'patches' since ${synced:0:7}, and the folder has changes 'patches' lacks -- set them aside, merge, and redo them on top: a merge now would publish the rewritten-away commits again with the next push" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  git diff --quiet HEAD
}

@test "merge: --no-fork-point merges a rebased upstream branch from Git's merge base, so its dropped patch conflicts" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge --no-fork-point vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: conflict -- resolve it"* ]]
}

@test "merge: without the fetched branch's reflog, e.g. in a clone that fetched only after the rebase, a rebased branch's dropped patch conflicts, as in Git" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  cd "$monorepo"
  git reflog expire --expire=all --all
  run cmd_merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: conflict -- resolve it"* ]]
}

@test "merge: after .splice switches to another upstream branch, a patch only the old, deleted branch had is kept: that's no rewrite" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  seed_bare_repo "$upstream" "patch" patches
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" vendor/a patches
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.origin.default-branch patches
  git commit -q -a --amend --no-edit
  seed_bare_repo "$upstream" "release" main release.txt
  git config --file vendor/a/.splice upstream.origin.default-branch main
  git commit -q -m "vendor/a: follow main" -- vendor/a/.splice
  git -C "$upstream" branch -q -D patches
  fetch_splice "$monorepo" "$upstream" vendor/a
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/file.txt)" = "$(printf 'seed\npatch')" ]
  [ "$(cat vendor/a/release.txt)" = "release" ]
}

@test "merge: a rebased upstream branch that already has the pushed local commit is merged, and the rebuild is that branch" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  cd "$monorepo"
  # Undo the rebase: patches is the two patches again, and gets a local commit
  # pushed on top of it.
  git -C "$upstream" update-ref refs/heads/patches "$(splice_config vendor/a commit)"
  fetch_splice "$monorepo" "$upstream" vendor/a
  commit_local "$monorepo" vendor/a "local change" local.txt
  splice push vendor/a >/dev/null
  # The fork rebases patches onto main, which took the first patch reworded:
  # the other patch and the local commit are left on top.
  local fork="$BATS_TEST_TMPDIR/fork" rebased
  git clone -q "$upstream" "$fork"
  git -C "$fork" checkout -q main
  git -C "$fork" checkout origin/patches -- other.txt
  git -C "$fork" -c user.name=Test -c user.email=test@example.com commit -q -m "other patch"
  git -C "$fork" checkout origin/patches -- local.txt
  git -C "$fork" -c user.name=Test -c user.email=test@example.com commit -q -m "local change"
  git -C "$fork" push -q --force origin main:patches
  rebased="$(git -C "$upstream" rev-parse patches)"
  fetch_splice "$monorepo" "$upstream" vendor/a
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a commit)" = "$rebased" ]
  [ "$(rebuild_splice vendor/a)" = "$rebased" ]
}

@test "merge: right after a push, nothing is recorded: the rebuild is the upstream branch" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: nothing to merge" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge --bump: right after a push, records the upstream branch, so the rebuild starts there" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  local before target
  before="$(git rev-parse HEAD)"
  target="$(git rev-parse "$(upstream_refs "$upstream")main")"
  run cmd_merge --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: bumped the synced commit to ${target:0:7}" ]
  [ "$(git rev-parse HEAD^)" = "$before" ]
  [ "$(git diff --name-only HEAD^ HEAD)" = "vendor/a/.splice" ]
  [ "$(git log -1 --format=%s)" = "splice: bump vendor/a from main at ${target:0:7}" ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
  [ "$(splice_last_sync vendor/a HEAD)" = "$(git rev-parse HEAD)" ]
  [ "$(rebuild_splice vendor/a)" = "$target" ]
}

@test "merge --bump: a later push sends the same commit as without the bump" {
  # The commit is made twice, and both must get the same hash.
  export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z
  scenario_pushed_then_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local unbumped
  unbumped="$(rebuild_splice vendor/a)"
  git reset -q --hard HEAD^
  cmd_merge --bump vendor/a >/dev/null
  commit_local "$monorepo" vendor/a "later change"
  [ "$(rebuild_splice vendor/a)" = "$unbumped" ]
}

@test "merge --bump: while ahead, the unpushed commit stays in the rebuild" {
  scenario_pushed_then_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local before target
  before="$(rebuild_splice vendor/a)"
  target="$(git rev-parse "$(upstream_refs "$upstream")main")"
  run cmd_merge --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
  [ "$(rebuild_splice vendor/a)" = "$before" ]
  classify_splice vendor/a main
  [ "$SPLICE_STATE" = push ]
}

@test "merge --bump: nothing to bump once the synced commit is the upstream branch" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_merge --bump vendor/a >/dev/null
  local before
  before="$(git rev-parse HEAD)"
  run cmd_merge --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: nothing to bump -- already synced at $(splice_config vendor/a commit | cut -c1-7)" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge --bump: nothing to bump while ahead of the upstream branch it's synced at, with the same message" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  cmd_merge --bump vendor/a >/dev/null
  commit_local "$monorepo" vendor/a "unpushed change"
  local before
  before="$(git rev-parse HEAD)"
  run cmd_merge --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: nothing to bump -- already synced at $(splice_config vendor/a commit | cut -c1-7)" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge --bump: never moves the synced commit back to a stale upstream ref" {
  scenario_pushed_then_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local ref synced before
  ref="$(upstream_refs "$upstream")main"
  cmd_merge --bump vendor/a >/dev/null
  synced="$(splice_config vendor/a commit)"
  git update-ref "$ref" "$synced^"
  before="$(git rev-parse HEAD)"
  run cmd_merge --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: nothing to bump -- the fetched 'main' is older than the synced commit" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge --bump: gives a splice that init made and push published its first synced commit" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  splice init lib/a "$upstream" >/dev/null 2>&1
  splice push lib/a >/dev/null 2>&1
  [ -z "$(splice_config lib/a commit)" ]
  run cmd_merge --bump lib/a
  [ "$status" -eq 0 ]
  [ "$(splice_config lib/a commit)" = "$(git -C "$upstream" rev-parse main)" ]
}

@test "merge: a push of an edited rebuild becomes the synced commit, so the original commit is never pushed" {
  scenario_edited_before_push "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt edited
  rebuilt="$(rebuild_splice vendor/a)"
  edited="$(git commit-tree "$rebuilt^{tree}" -p "$rebuilt^" -m "fix the parser")"
  git push -q "$upstream" "$edited:refs/heads/main"
  splice fetch >/dev/null
  run cmd_merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a commit)" = "$edited" ]
  commit_local "$monorepo" vendor/a "another fix"
  splice push vendor/a >/dev/null
  [ "$(git -C "$upstream" log --format=%s main)" = "another fix"$'\n'"fix the parser"$'\n'"seed" ]
}

@test "merge: refuses to guess on unrelated history" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"share no history -- pick a side"* ]]
}

@test "merge: asks for a fetch first" {
  scenario_never_fetched "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"not fetched yet"* ]]
}

@test "merge: needs paths or --all" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run cmd_merge
  [ "$status" -eq 1 ]
  [[ "$output" == *"which splice?"* ]]
}

@test "merge: leaves the worktree's other changes alone" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  echo "work in progress" >wip.txt
  cmd_merge vendor/a
  [ "$(cat wip.txt)" = "work in progress" ]
  [ "$(git status --porcelain)" = "?? wip.txt" ]
}

@test "pull: fetches, then merges" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  cd "$monorepo"
  run cmd_pull vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a fetched (main moved"* ]]
  [[ "$output" == *"vendor/a: pulled"* ]]
  [ "$(git log -1 --format=%s)" = "splice: pull vendor/a from main at $(git rev-parse --short=7 "$(upstream_refs "$upstream")main")" ]
}

@test "pull --bump: fetches, then bumps" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  local before target
  before="$(git rev-parse HEAD)"
  target="$(git -C "$upstream" rev-parse main)"
  run cmd_pull --bump vendor/a
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "ok   vendor/a: bumped the synced commit to ${target:0:7}" ]
  [ "$(git rev-parse HEAD^)" = "$before" ]
  [ "$(git diff --name-only HEAD^ HEAD)" = "vendor/a/.splice" ]
  [ "$(git log -1 --format=%s)" = "splice: bump vendor/a from main at ${target:0:7}" ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
}

@test "pull: a failed fetch is reported, the rest still merges" {
  scenario_shared_remote_url "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  cd "$monorepo"
  git config --file vendor/b/.splice upstream.origin.url "$BATS_TEST_TMPDIR/nowhere.git"
  git commit -q -am "break vendor/b"
  run cmd_pull --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: pulled"* ]]
  [[ "$output" == *"Not fetched: vendor/b"* ]]
}

@test "merge: in a shallow clone that cuts off the last sync, refuses instead of recording the upstream branch" {
  scenario_up_to_date "$monorepo" "$upstream"
  git clone -q --depth 1 "file://$monorepo" "$BATS_TEST_TMPDIR/shallow"
  cd "$BATS_TEST_TMPDIR/shallow"
  splice fetch vendor/a >/dev/null
  local head
  head="$(git rev-parse HEAD)"
  run splice merge vendor/a
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   vendor/a: this shallow clone may cut off where its rebuild starts, at ${head:0:7} -- run 'git fetch --unshallow'" ]
  [ "${lines[1]}" = "!!   Failed: vendor/a" ]
  [ "${#lines[@]}" -eq 2 ]
  [ "$(git rev-parse HEAD)" = "$head" ]
  [ -z "$(git status --porcelain)" ]
}
