# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_diverged_then_pulled() {
  local monorepo="$1" upstream="$2"
  scenario_up_to_date "$monorepo" "$upstream"
  commit_local "$monorepo" "vendor/a" "local change" local.txt
  seed_bare_repo "$upstream" "upstream change" main upstream.txt
  (cd "$monorepo" && splice pull vendor/a >/dev/null 2>&1)
}
