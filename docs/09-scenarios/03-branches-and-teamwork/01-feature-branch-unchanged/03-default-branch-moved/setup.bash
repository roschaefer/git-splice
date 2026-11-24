# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_default_branch_moved() {
  local monorepo="$1" upstream="$2"
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  seed_bare_repo "$upstream" "l: fix upstream"
  fetch_splice "$monorepo" "$upstream" vendor/a
}
