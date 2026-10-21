# See README.md in this directory.
scenario_patch_branch_rebased() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  # A fork's patch branch: the upstream's main plus a patch of its own.
  seed_bare_repo "$upstream" "patch" patches
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a" patches
  (
    cd "$monorepo"
    git config --file vendor/a/.splice upstream.origin.default-branch patches
    git commit -q -a --amend --no-edit
  )

  # The upstream's main takes the patch, reworded, and the patch branch is
  # rebased onto it: the patch drops out, the branch is main again.
  seed_bare_repo "$upstream" "patch, reworded upstream"
  git -C "$upstream" update-ref refs/heads/patches refs/heads/main
  fetch_splice "$monorepo" "$upstream" "vendor/a"
}
