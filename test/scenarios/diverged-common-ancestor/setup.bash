# See README.md in this directory.
scenario_diverged_common_ancestor() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  commit_local "$monorepo" "vendor/a" "local change"
  seed_bare_repo "$upstream" "upstream change"
  fetch_splice "$monorepo" "$upstream" "vendor/a"
}
