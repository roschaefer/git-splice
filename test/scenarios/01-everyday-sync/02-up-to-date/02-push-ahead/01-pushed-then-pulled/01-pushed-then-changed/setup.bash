# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_pushed_then_changed() {
  local monorepo="$1" upstream="$2"
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  commit_local "$monorepo" "vendor/a" "later change"
}
