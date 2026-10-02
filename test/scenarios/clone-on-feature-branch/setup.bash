# See README.md in this directory.
scenario_clone_on_feature_branch() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  git -C "$monorepo" checkout -q -b feature
}
