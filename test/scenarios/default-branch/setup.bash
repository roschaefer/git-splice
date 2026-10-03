# See README.md in this directory.
scenario_default_branch() {
  local monorepo="$1" upstream="$2"
  # The upstream's default branch is master, the monorepo's is main.
  make_bare_repo "$upstream" master
  seed_bare_repo "$upstream" "seed" master
  init_monorepo "$monorepo"
  (cd "$monorepo" && splice clone "$upstream" vendor/a >/dev/null 2>&1)
  commit_local "$monorepo" "vendor/a" "local change"
}
