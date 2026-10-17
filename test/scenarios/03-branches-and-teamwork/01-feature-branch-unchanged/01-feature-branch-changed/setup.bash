# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_feature_branch_changed() {
  local monorepo="$1" upstream="$2"
  scenario_feature_branch_unchanged "$monorepo" "$upstream"
  commit_local "$monorepo" "vendor/a" "local change"
}
