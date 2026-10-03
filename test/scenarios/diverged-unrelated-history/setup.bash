# See README.md in this directory.
scenario_diverged_unrelated_history() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  commit_local "$monorepo" "vendor/a" "local change"

  # Blow away upstream and replace it with a completely unrelated history.
  rm -rf "$upstream"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "brand new unrelated history"
  fetch_splice "$monorepo" "$upstream" "vendor/a"
}
