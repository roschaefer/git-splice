# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_pushed_then_pulled() {
  local monorepo="$1" upstream="$2"
  scenario_push_ahead "$monorepo" "$upstream"
  (cd "$monorepo" && splice push vendor/a >/dev/null 2>&1)
}
