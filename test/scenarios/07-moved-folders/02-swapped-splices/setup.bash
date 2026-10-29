# See README.md in this directory.
scenario_swapped_splices() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  commit_local "$monorepo" "vendor/a" "a's unpushed work" a.txt
  commit_local "$monorepo" "vendor/b" "b's first version" b.txt
  # An empty repository, created for vendor/b to be published to.
  make_bare_repo "$upstream-b"
}
