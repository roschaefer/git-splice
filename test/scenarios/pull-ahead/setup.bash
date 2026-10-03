# See README.md in this directory.
scenario_pull_ahead() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  seed_bare_repo "$upstream" "upstream change"
  fetch_splice "$monorepo" "$upstream" "vendor/a"
}
