# See README.md in this directory.
scenario_shared_remote_url() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  add_splice "$monorepo" "$upstream" "vendor/b"
}
