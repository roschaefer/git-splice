# See README.md in this directory. The unpushed commit's message is $3,
# "local change" by default.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_push_ahead() {
  local monorepo="$1" upstream="$2" message="${3:-local change}"
  scenario_up_to_date "$monorepo" "$upstream"
  commit_local "$monorepo" "vendor/a" "$message"
}
