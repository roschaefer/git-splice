setup() {
  load 'helpers/fixtures'
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
  load 'walkthrough/rebase-feature-branch/setup'
  load 'scenarios/03-branches-and-teamwork/06-teammate-pulled/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

@test "merge: adds exactly one first-parent commit and no upstream ancestors" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run splice merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD^)" = "$before" ]
  [ "$(git rev-list --parents -1 HEAD | wc -w)" -eq 2 ]
  ! git merge-base --is-ancestor "$(upstream_refs "$upstream")main" HEAD
  [ "$(git log -1 --format=%s)" = "splice: merge vendor/a from main at $(git rev-parse --short=7 "$(upstream_refs "$upstream")main")" ]
}

@test "merge: a divergence pulled after a move joins the unpushed commit from before the move with the upstream's, as git pull would" {
  scenario_up_to_date "$monorepo" "$upstream"
  commit_local "$monorepo" vendor/a "local change" local.txt
  cd "$monorepo"
  mkdir -p libs
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  seed_bare_repo "$upstream" "upstream change"
  splice pull libs/a
  [ "$(cat libs/a/local.txt)" = "local change" ]
  grep -q "upstream change" libs/a/file.txt
  local rebuilt
  rebuilt="$(splice rebuild libs/a)"
  [ "$(git log -1 --format=%s "$rebuilt^1")" = "local change" ]
  [ "$(git rev-parse "$rebuilt^2")" = "$(git -C "$upstream" rev-parse main)" ]
  splice push libs/a
  [ "$(git -C "$upstream" rev-parse main)" = "$rebuilt" ]
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
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"vendor/a: upstream has a submodule, libs/inner, which nobody could check out"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge: brings upstream's content and records the synced commit" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  splice merge vendor/a
  [ "$(git rev-parse HEAD:vendor/a/file.txt)" = "$(git rev-parse "$(upstream_refs "$upstream")main":file.txt)" ]
  [ "$(splice_config vendor/a commit)" = "$(git rev-parse "$(upstream_refs "$upstream")main")" ]
  [ "$(splice_state vendor/a)" = up-to-date ]
}

@test "merge: keeps the splice's id" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local id
  id="$(splice_config vendor/a id)"
  splice merge vendor/a
  [ "$(splice_config vendor/a id)" = "$id" ]
}

@test "merge: refuses an upstream that brings in a .splice at its root" {
  scenario_pull_ahead "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "[splice]" main .splice
  cd "$monorepo"
  splice fetch vendor/a >/dev/null
  local before
  before="$(git rev-parse HEAD)"
  run splice merge vendor/a
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
  run splice merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/local.txt)" = "local change" ]
  grep -q "upstream change" vendor/a/file.txt
  [ "$(splice_state vendor/a)" = push ]
}

@test "merge: a conflict is resolved like any other, and git commit finishes it" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT"*"vendor/a/file.txt"* ]]
  [[ "$output" == *"resolve it, then 'git commit'"* ]]
  [ "$(git status --porcelain vendor/a/file.txt)" = "UU vendor/a/file.txt" ]
  printf 'seed\nboth\n' >vendor/a/file.txt
  git add vendor/a/file.txt
  git commit -q --no-edit
  [[ "$(git log -1 --format=%s)" == "splice: merge vendor/a from main at "* ]]
  [ "$(splice_config vendor/a commit)" = "$(git rev-parse "$(upstream_refs "$upstream")main")" ]
  [ "$(splice_state vendor/a)" = push ]
}

@test "merge: stops at a conflict and doesn't start the next splice" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  add_splice "$monorepo" "$upstream" vendor/b
  cd "$monorepo"
  run splice merge --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not merged yet: vendor/b"* ]]
}

@test "merge: nothing to do when up to date or only ahead" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run splice merge vendor/a
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
  run splice merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD^)" = "$before" ]
  [ "$(git diff --name-only HEAD^ HEAD)" = "vendor/a/.splice" ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
  commit_local "$monorepo" vendor/a "local change"
  [ "$(splice_state vendor/a)" = push ]
  [ "$(git rev-parse "$(splice rebuild vendor/a)^")" = "$target" ]
}

@test "merge: a rebased upstream branch merges from its fork point, where the branch was before the rebase, so its dropped patch doesn't conflict" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  cd "$monorepo"
  local target
  target="$(git rev-parse "$(upstream_refs "$upstream")patches")"
  run splice merge vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: merged ${target:0:7}" ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
  [ "$(git rev-parse HEAD:vendor/a/file.txt)" = "$(git rev-parse "$target:file.txt")" ]
  [ "$(splice rebuild vendor/a)" = "$target" ]
}

@test "merge: a rebased upstream branch is refused while the folder has changes it lacks, which the next push would publish on the dropped patch" {
  scenario_unpushed_local_commit "$monorepo" "$upstream"
  cd "$monorepo"
  local before synced
  before="$(git rev-parse HEAD)"
  synced="$(splice_config vendor/a commit)"
  run splice merge vendor/a
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   vendor/a: upstream rewrote 'patches' since ${synced:0:7}, and the folder has changes 'patches' lacks -- run 'git splice merge --rebase vendor/a' to redo them on top: a merge now would publish the rewritten-away commits again with the next push" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  git diff --quiet HEAD
}

@test "merge: --no-fork-point merges a rebased upstream branch from Git's merge base, so its dropped patch conflicts" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge --no-fork-point vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: conflict -- resolve it"* ]]
}

@test "merge: without the fetched branch's reflog, e.g. in a clone that fetched only after the rebase, a rebased branch's dropped patch conflicts, as in Git" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  cd "$monorepo"
  git reflog expire --expire=all --all
  run splice merge vendor/a
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
  run splice merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/file.txt)" = "$(printf 'seed\npatch')" ]
  [ "$(cat vendor/a/release.txt)" = "release" ]
}

@test "merge: --branch merges the named upstream branch on a branch the upstream has none for, without changing .splice's default-branch" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  cd "$monorepo"
  git switch -q -c take-the-release
  local target
  target="$(git rev-parse "$(upstream_refs "$upstream")patches")"
  run splice merge vendor/a
  [ "$output" = "ok   vendor/a: upstream has no 'take-the-release' branch -- nothing to merge" ]
  run splice merge --branch patches vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: merged ${target:0:7}" ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
  [ "$(git config --file vendor/a/.splice upstream.origin.default-branch)" = patches ]
  [ "$(git log -1 --format=%s)" = "splice: merge vendor/a from patches at ${target:0:7}" ]
}

@test "merge: --branch naming a branch the upstream lacks, e.g. a typo, fails, unlike the monorepo branch's own missing name" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run splice merge --branch patchs vendor/a
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   vendor/a: upstream has no 'patchs' branch, which --branch names" ]
  run splice merge --branch bad..name vendor/a
  [ "$status" -eq 1 ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge: --branch needs a branch's name" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge vendor/a --branch
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --branch needs an upstream branch's name" ]
}

@test "merge --rebase: takes a rebased upstream branch in under the unpushed local commit, so the rebuild is that commit on top of the branch" {
  scenario_unpushed_local_commit "$monorepo" "$upstream"
  cd "$monorepo"
  local target
  target="$(git rev-parse "$(upstream_refs "$upstream")patches")"
  run splice merge --rebase vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: merged ${target:0:7}, and rebased 1 commit onto it" ]
  [ "$(git log --format=%s -3)" = "local change
splice: merge vendor/a from patches at ${target:0:7}
a: add vendor/a" ]
  [ "$(git rev-parse HEAD~1:vendor/a/file.txt)" = "$(git rev-parse "$target:file.txt")" ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
  local rebuilt
  rebuilt="$(splice rebuild vendor/a)"
  [ "$(git rev-parse "$rebuilt^")" = "$target" ]
  [ "$(git log -1 --format=%s "$rebuilt")" = "local change" ]
}

@test "merge --rebase: a diverged upstream branch goes under the local commit, so the rebuild is linear" {
  scenario_push_ahead "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change" main upstream.txt
  fetch_splice "$monorepo" "$upstream" vendor/a
  cd "$monorepo"
  local target
  target="$(git rev-parse "$(upstream_refs "$upstream")main")"
  run splice merge --rebase vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse "$(splice rebuild vendor/a)^")" = "$target" ]
}

@test "merge --rebase: without local commits since the synced commit, merges as without it" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  cd "$monorepo"
  local target
  target="$(git rev-parse "$(upstream_refs "$upstream")patches")"
  run splice merge --rebase vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: merged ${target:0:7}" ]
}

@test "merge --rebase: refuses when a remote-tracking branch has the commits it would rewrite" {
  scenario_unpushed_local_commit "$monorepo" "$upstream"
  cd "$monorepo"
  git update-ref refs/remotes/origin/main HEAD
  local before
  before="$(git rev-parse HEAD)"
  run splice merge --rebase vendor/a
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   vendor/a: 'origin/main' has commits since $(git rev-parse --short=7 HEAD~1), which --rebase would rewrite -- merge on a branch nobody else has, e.g. a pull request's" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge --rebase: on a conflict, stops in the rebase, and the next merge waits for it" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge --rebase vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: conflict while rebasing onto the merge -- resolve it, then 'git rebase --continue' (or 'git rebase --abort' to give up)"* ]]
  [ -d "$(git rev-parse --git-path rebase-merge)" ]
  run splice merge vendor/a
  [ "$output" = "!!   a cherry-pick, merge or rebase is in progress -- conclude it first" ]
}

@test "merge --rebase: with uncommitted changes, says the rebase didn't start, not that it conflicts" {
  scenario_unpushed_local_commit "$monorepo" "$upstream"
  cd "$monorepo"
  echo "uncommitted" >>vendor/a/file.txt
  local before
  before="$(git rev-parse HEAD)"
  run splice merge --rebase vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: git rebase didn't start, see above -- nothing changed"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge --rebase: with rebase.autoStash set, uncommitted changes still keep the rebase from starting" {
  scenario_unpushed_local_commit "$monorepo" "$upstream"
  cd "$monorepo"
  git config rebase.autoStash true
  echo "uncommitted" >>vendor/a/file.txt
  local before
  before="$(git rev-parse HEAD)"
  run splice merge --rebase vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: git rebase didn't start, see above -- nothing changed"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ -z "$(git stash list)" ]
}

@test "merge --rebase: with rebase.updateRefs set, leaves other local branches on the commits it rewrites alone" {
  scenario_unpushed_local_commit "$monorepo" "$upstream"
  cd "$monorepo"
  git config rebase.updateRefs true
  git branch -q other HEAD
  local before
  before="$(git rev-parse HEAD)"
  run splice merge --rebase vendor/a
  [ "$status" -eq 0 ]
  [ "$(git rev-parse other)" = "$before" ]
  [ "$(git rev-parse HEAD)" != "$before" ]
}

@test "merge --rebase: on a conflict, the splices after it wait for 'git rebase --continue'" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  add_splice "$monorepo" "$upstream" vendor/b
  cd "$monorepo"
  run splice merge --rebase --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   Not merged yet: vendor/b -- resolve the conflict, run 'git rebase --continue', then re-run merge"* ]]
}

@test "merge --rebase: refuses a splice that init made and push published, which has no synced commit to rebase onto" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  splice init lib/a "$upstream" >/dev/null 2>&1
  splice push lib/a >/dev/null 2>&1
  [ -z "$(splice_config lib/a commit)" ]
  seed_bare_repo "$upstream" "upstream change" main upstream.txt
  splice fetch lib/a >/dev/null
  run splice merge --rebase lib/a
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   lib/a: no synced commit recorded yet, e.g. after init -- nothing to rebase onto; merge without --rebase" ]
}

@test "merge --rebase: refuses a merge commit among the commits to rebase, whose own changes the rebase would drop" {
  scenario_unpushed_local_commit "$monorepo" "$upstream"
  cd "$monorepo"
  git switch -q -c side HEAD~1
  commit_local "$monorepo" vendor/a "side change" side.txt
  git switch -q main
  git merge -q --no-ff -m "merge side" side
  local before
  before="$(git rev-parse HEAD)"
  run splice merge --rebase vendor/a
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   vendor/a: there's a merge commit since $(git rev-parse --short=7 HEAD~1~1), whose own changes --rebase would drop -- merge without --rebase" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge --rebase: refuses with its message when a remote-tracking branch has several of the commits it would rewrite" {
  scenario_unpushed_local_commit "$monorepo" "$upstream"
  cd "$monorepo"
  commit_local "$monorepo" vendor/a "another change" another.txt
  commit_local "$monorepo" vendor/a "a third change" third.txt
  git update-ref refs/remotes/origin/main HEAD
  run splice merge --rebase vendor/a
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   vendor/a: 'origin/main' has commits since $(git rev-parse --short=7 HEAD~3), which --rebase would rewrite -- merge on a branch nobody else has, e.g. a pull request's" ]
}

@test "merge --rebase: refuses when the upstream branch lacks the synced commit and its reflog doesn't show it had it, e.g. after 'git rebase main', whose changes it would drop" {
  scenario_feature_branch_behind_default_branch "$monorepo" "$upstream"
  git -C "$monorepo" rebase -q main
  cd "$monorepo"
  local before synced
  before="$(git rev-parse HEAD)"
  synced="$(splice_config vendor/a commit)"
  run splice merge --rebase vendor/a
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   vendor/a: 'feature' lacks the synced commit ${synced:0:7}, and its reflog here doesn't show it ever had it -- --rebase would drop that commit's changes" ]
  [[ "$output" != *"git splice"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge --rebase: in a fresh clone of the monorepo, whose reflog starts after the upstream rebased its branch, refuses with the same facts and suggests no push --force, which would overwrite that rebase" {
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  git clone -q "$monorepo" "$BATS_TEST_TMPDIR/clone"
  cd "$BATS_TEST_TMPDIR/clone"
  splice fetch vendor/a >/dev/null
  local synced
  synced="$(splice_config vendor/a commit)"
  run splice merge --rebase vendor/a
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   vendor/a: 'patches' lacks the synced commit ${synced:0:7}, and its reflog here doesn't show it ever had it -- --rebase would drop that commit's changes" ]
  [[ "$output" != *"--force"* ]]
}

@test "merge --rebase: once the upstream branch is rebased too, --rebase again takes the rebased upstream branch in under the local commits, without the copies a merge would join in" {
  scenario_feature_branch_behind_default_branch "$monorepo" "$upstream"
  git -C "$monorepo" rebase -q main
  commit_local "$monorepo" vendor/a "d: more work" more.txt
  local clone="$BATS_TEST_TMPDIR/clone"
  git clone -q -b feature "$upstream" "$clone"
  git -C "$clone" -c user.name=Test -c user.email=test@example.com rebase -q origin/main
  git -C "$clone" push -q --force origin feature
  cd "$monorepo"
  splice fetch vendor/a >/dev/null
  run splice merge --rebase vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log --format=%s -1 "$(splice rebuild vendor/a)")" = "d: more work" ]
  [ "$(git rev-parse "$(splice rebuild vendor/a)^")" = "$(git -C "$upstream" rev-parse feature)" ]
}

@test "merge --rebase: refuses by the upstream branch alone, also when no other upstream branch has the synced commit" {
  scenario_feature_branch_behind_default_branch "$monorepo" "$upstream"
  git -C "$monorepo" rebase -q main
  git -C "$upstream" update-ref refs/heads/main main~1
  cd "$monorepo"
  splice fetch vendor/a >/dev/null
  run splice merge --rebase vendor/a
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == *"'feature' lacks the synced commit"* ]]
}

@test "merge --rebase: without the fetched branch's reflog, e.g. in a clone that fetched only after the rebase, can't tell a rebased upstream branch from one that never had the synced commit, and refuses" {
  scenario_unpushed_local_commit "$monorepo" "$upstream"
  cd "$monorepo"
  git reflog expire --expire=all --all
  run splice merge --rebase vendor/a
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == *"'patches' lacks the synced commit"* ]]
}

@test "merge --rebase: takes the upstream branch in once it was rebased upstream too, and has the synced commit" {
  scenario_feature_branch_behind_default_branch "$monorepo" "$upstream"
  git -C "$monorepo" rebase -q main
  local clone="$BATS_TEST_TMPDIR/clone"
  git clone -q -b feature "$upstream" "$clone"
  git -C "$clone" -c user.name=Test -c user.email=test@example.com rebase -q origin/main
  git -C "$clone" push -q --force origin feature
  cd "$monorepo"
  splice fetch vendor/a >/dev/null
  run splice merge --rebase vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/lock.txt)" = "m: bump dep" ]
}

@test "merge: the suggested --rebase keeps the --branch the refused merge had" {
  scenario_unpushed_local_commit "$monorepo" "$upstream"
  cd "$monorepo"
  git switch -q -c take-the-release
  run splice merge --branch patches vendor/a
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == *"-- run 'git splice merge --rebase --branch patches vendor/a' to redo them on top"* ]]
}

@test "merge: --bump and --rebase don't go together" {
  scenario_unpushed_local_commit "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge --bump --rebase vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --bump and --rebase don't go together" ]
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
  run splice merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a commit)" = "$rebased" ]
  [ "$(splice rebuild vendor/a)" = "$rebased" ]
}

@test "merge: right after a push, nothing is recorded: the rebuild is the upstream branch" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run splice merge vendor/a
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
  run splice merge --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: bumped the synced commit to ${target:0:7}" ]
  [ "$(git rev-parse HEAD^)" = "$before" ]
  [ "$(git diff --name-only HEAD^ HEAD)" = "vendor/a/.splice" ]
  [ "$(git log -1 --format=%s)" = "splice: bump vendor/a from main at ${target:0:7}" ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
  [ "$(splice boundary vendor/a)" = "$(git rev-parse HEAD)" ]
  [ "$(splice rebuild vendor/a)" = "$target" ]
}

@test "merge --bump: a later push sends the same commit as without the bump" {
  # The commit is made twice, and both must get the same hash.
  export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z
  scenario_pushed_then_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local unbumped
  unbumped="$(splice rebuild vendor/a)"
  git reset -q --hard HEAD^
  splice merge --bump vendor/a >/dev/null
  commit_local "$monorepo" vendor/a "later change"
  [ "$(splice rebuild vendor/a)" = "$unbumped" ]
}

@test "merge --bump: while ahead, the unpushed commit stays in the rebuild" {
  scenario_pushed_then_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local before target
  before="$(splice rebuild vendor/a)"
  target="$(git rev-parse "$(upstream_refs "$upstream")main")"
  run splice merge --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a commit)" = "$target" ]
  [ "$(splice rebuild vendor/a)" = "$before" ]
  [ "$(splice_state vendor/a)" = push ]
}

@test "merge --bump: nothing to bump once the synced commit is the upstream branch" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  splice merge --bump vendor/a >/dev/null
  local before
  before="$(git rev-parse HEAD)"
  run splice merge --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: nothing to bump -- already synced at $(splice_config vendor/a commit | cut -c1-7)" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge --bump: nothing to bump while ahead of the upstream branch it's synced at, with the same message" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  splice merge --bump vendor/a >/dev/null
  commit_local "$monorepo" vendor/a "unpushed change"
  local before
  before="$(git rev-parse HEAD)"
  run splice merge --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a: nothing to bump -- already synced at $(splice_config vendor/a commit | cut -c1-7)" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge --bump: never moves the synced commit back to a stale upstream ref" {
  scenario_pushed_then_changed "$monorepo" "$upstream"
  cd "$monorepo"
  local ref synced before
  ref="$(upstream_refs "$upstream")main"
  splice merge --bump vendor/a >/dev/null
  synced="$(splice_config vendor/a commit)"
  git update-ref "$ref" "$synced^"
  before="$(git rev-parse HEAD)"
  run splice merge --bump vendor/a
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
  run splice merge --bump lib/a
  [ "$status" -eq 0 ]
  [ "$(splice_config lib/a commit)" = "$(git -C "$upstream" rev-parse main)" ]
}

@test "merge: a push of an edited rebuild becomes the synced commit, so the original commit is never pushed" {
  scenario_edited_before_push "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt edited
  rebuilt="$(splice rebuild vendor/a)"
  edited="$(git commit-tree "$rebuilt^{tree}" -p "$rebuilt^" -m "fix the parser")"
  git push -q "$upstream" "$edited:refs/heads/main"
  splice fetch >/dev/null
  run splice merge vendor/a
  [ "$status" -eq 0 ]
  [ "$(splice_config vendor/a commit)" = "$edited" ]
  commit_local "$monorepo" vendor/a "another fix"
  splice push vendor/a >/dev/null
  [ "$(git -C "$upstream" log --format=%s main)" = "another fix"$'\n'"fix the parser"$'\n'"seed" ]
}

@test "merge: refuses to guess on unrelated history" {
  scenario_diverged_unrelated_history "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"share no history -- pick a side"* ]]
}

@test "merge: asks for a fetch first" {
  scenario_never_fetched "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"not fetched yet"* ]]
}

@test "merge: asks for a fetch when a teammate's pull names a synced commit that isn't here" {
  scenario_teammate_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  local synced
  synced="$(splice_config vendor/a commit)"
  run splice merge vendor/a
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "??   vendor/a: synced commit ${synced:0:7} isn't here -- run 'git splice fetch vendor/a', or check that upstream has it" ]
}

@test "pull: fetches a teammate's synced commit, and has nothing to pull then" {
  scenario_teammate_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a: nothing to pull"* ]]
}

@test "pull: offers to pick a side when upstream doesn't have the synced commit any more" {
  scenario_push_ahead "$monorepo" "$upstream"
  rm -rf "$upstream"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "brand new unrelated history"
  cd "$monorepo"
  git for-each-ref --format='delete %(refname)' refs/splices/ | git update-ref --stdin
  git reflog expire --expire=now --all && git gc -q --prune=now
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"share no history -- pick a side"* ]]
}

@test "merge -m: the commit gets the message instead of the default one, and .splice still records the synced commit" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge -m "b: take the faster parser" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%B)" = "b: take the faster parser" ]
  [ "$(splice_config vendor/a commit)" = "$(git rev-parse "$(upstream_refs "$upstream")main")" ]
  [ "$(splice_state vendor/a)" = up-to-date ]
}

@test "merge -m: refuses several splices and --all, before merging any: each gets a commit of its own" {
  scenario_pull_ahead "$monorepo" "$upstream"
  add_splice "$monorepo" "$upstream" vendor/b
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run splice merge -m "take both" vendor/a vendor/b
  [ "$status" -eq 1 ]
  [[ "$output" == *"-m names one splice's commit -- name one path, not several or --all"* ]]
  run splice merge -m "take all" --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"-m names one splice's commit"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "merge -m: on a conflict, git commit keeps the message" {
  scenario_diverged_common_ancestor "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge -m "c: merge upstream's change" vendor/a
  [ "$status" -eq 1 ]
  printf 'seed\nboth\n' >vendor/a/file.txt
  git add vendor/a/file.txt
  git commit -q --no-edit
  [ "$(git log -1 --format=%s)" = "c: merge upstream's change" ]
}

@test "merge --rebase -m: the commit the rebased ones go on top of gets the message" {
  scenario_unpushed_local_commit "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge --rebase -m "d: take the rebased patches" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log --format=%s -3)" = "local change
d: take the rebased patches
a: add vendor/a" ]
}

@test "merge --bump -m: the bump gets the message" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge --bump -m "e: bump vendor/a" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "e: bump vendor/a" ]
  [ "$(git diff --name-only HEAD^ HEAD)" = "vendor/a/.splice" ]
}

@test "merge: needs paths or --all" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run splice merge
  [ "$status" -eq 1 ]
  [[ "$output" == *"which splice?"* ]]
}

@test "merge: leaves the worktree's other changes alone" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  echo "work in progress" >wip.txt
  splice merge vendor/a
  [ "$(cat wip.txt)" = "work in progress" ]
  [ "$(git status --porcelain)" = "?? wip.txt" ]
}

@test "pull: fetches, then merges" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  cd "$monorepo"
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"vendor/a fetched (main moved"* ]]
  [[ "$output" == *"vendor/a: pulled"* ]]
  [ "$(git log -1 --format=%s)" = "splice: pull vendor/a from main at $(git rev-parse --short=7 "$(upstream_refs "$upstream")main")" ]
}

@test "pull -m: the commit gets the message, and several splices are refused before any fetch" {
  scenario_up_to_date "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  cd "$monorepo"
  run splice pull -m "f: pull the change" --all
  [ "$status" -eq 1 ]
  [[ "$output" != *"fetched"* ]]
  run splice pull -m "f: pull the change" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "f: pull the change" ]
}

@test "push: takes no -m, it writes no commit to the monorepo" {
  scenario_push_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run splice push -m "g: publish" vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option: -m"* ]]
}

@test "pull --bump: fetches, then bumps" {
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  cd "$monorepo"
  local before target
  before="$(git rev-parse HEAD)"
  target="$(git -C "$upstream" rev-parse main)"
  run splice pull --bump vendor/a
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
  run splice pull --all
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
