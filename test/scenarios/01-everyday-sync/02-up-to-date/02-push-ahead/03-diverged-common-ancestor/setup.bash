# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_diverged_common_ancestor() {
  local monorepo="$1" upstream="$2"
  scenario_push_ahead "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "upstream change"
  fetch_splice "$monorepo" "$upstream" "vendor/a"
}
