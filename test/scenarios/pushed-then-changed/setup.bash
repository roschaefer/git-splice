# See README.md in this directory.
scenario_pushed_then_changed() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  commit_local "$monorepo" "vendor/a" "pushed change"
  (cd "$monorepo" && splice push vendor/a >/dev/null 2>&1)
  commit_local "$monorepo" "vendor/a" "later change"
}
