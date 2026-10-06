# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_moved_with_unpushed_commits() {
  local monorepo="$1" upstream="$2"
  scenario_push_ahead "$monorepo" "$upstream"
  mkdir -p "$monorepo/libs"
}
