# See README.md in this directory.
scenario_diverged_then_pulled() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"
  commit_local "$monorepo" "vendor/a" "local change" local.txt
  seed_bare_repo "$upstream" "upstream change" main upstream.txt
  (cd "$monorepo" && splice pull vendor/a >/dev/null 2>&1)
}
