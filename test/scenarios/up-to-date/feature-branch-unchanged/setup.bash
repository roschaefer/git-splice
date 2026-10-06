# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_feature_branch_unchanged() {
  local monorepo="$1" upstream="$2"
  scenario_up_to_date "$monorepo" "$upstream"
  git -C "$monorepo" checkout -q -b feature
}
