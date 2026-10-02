# See README.md in this directory.
scenario_nested_splices() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  # The upstream uses git splice itself: its extra/ is one of its splices.
  seed_bare_repo "$upstream" "[splice]" main extra/.splice
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/pkg"
}
