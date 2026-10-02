# See README.md in this directory.
scenario_feature_branch_changed() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  git -C "$monorepo" checkout -q -b feature
  commit_local "$monorepo" "vendor/a" "local change"
}
