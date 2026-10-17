# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_stacked_branch() {
  local monorepo="$1" upstream="$2"
  scenario_feature_branch_changed "$monorepo" "$upstream"
  (cd "$monorepo" && splice push vendor/a >/dev/null 2>&1)
  git -C "$monorepo" checkout -q -b stacked
  # Work outside the splice: the stacked branch doesn't change vendor/a.
  commit_local "$monorepo" "app" "app work"
}
