# See README.md in this directory.
scenario_clone_from_submodule() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    git -c protocol.file.allow=always submodule add -q "$upstream" vendor/a
    git commit -q -m "add vendor/a as a submodule"
  )
  seed_bare_repo "$upstream" "newer"
}
