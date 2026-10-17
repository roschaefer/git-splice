# See README.md in this directory.
scenario_init_new_upstream() {
  local monorepo="$1" upstream="$2"
  # An empty repository, created for the folder to be published to.
  make_bare_repo "$upstream"
  init_monorepo "$monorepo"
  commit_local "$monorepo" "lib/a" "first version"
  commit_local "$monorepo" "lib/a" "second version"
}
