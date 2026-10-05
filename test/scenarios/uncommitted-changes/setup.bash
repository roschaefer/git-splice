# See README.md in this directory.
scenario_uncommitted_changes() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  commit_local "$monorepo" "vendor/a" "committed change"
  echo "uncommitted change" >>"$monorepo/vendor/a/file.txt"
}
