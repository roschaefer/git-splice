# See README.md in this directory.
scenario_submodule_in_linked_worktree() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    git -c protocol.file.allow=always submodule add -q "$upstream" vendor/a
    git commit -q -m "add vendor/a as a submodule"
    git worktree add -q -b feature ../feature
    git -C ../feature -c protocol.file.allow=always submodule update -q --init
  )
}
