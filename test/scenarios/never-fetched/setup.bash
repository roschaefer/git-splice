# See README.md in this directory.
scenario_never_fetched() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  # As in a fresh clone of the monorepo: the commits are there, the
  # private refs with upstream's branches aren't.
  git -C "$monorepo" for-each-ref --format='delete %(refname)' refs/splices/ |
    git -C "$monorepo" update-ref --stdin
}
