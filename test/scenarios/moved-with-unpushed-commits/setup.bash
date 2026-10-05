# See README.md in this directory.
scenario_moved_with_unpushed_commits() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  commit_local "$monorepo" "vendor/a" "important local change"
  mkdir -p "$monorepo/libs"
}
