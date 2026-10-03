# See README.md in this directory.
scenario_nested_splices() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/pkg"
  add_splice "$monorepo" "$upstream" "vendor/pkg/extra"
}
