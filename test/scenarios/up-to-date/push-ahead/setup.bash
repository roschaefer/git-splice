# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_push_ahead() {
  local monorepo="$1" upstream="$2"
  scenario_up_to_date "$monorepo" "$upstream"
  commit_local "$monorepo" "vendor/a" "local change"
}
