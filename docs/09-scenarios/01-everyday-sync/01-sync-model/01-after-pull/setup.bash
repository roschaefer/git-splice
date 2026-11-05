# See README.md in this directory. Commits are named as in the drawing
# there, after-pull.drawio.svg.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_after_pull() {
  local monorepo="$1" upstream="$2"
  scenario_sync_model "$monorepo" "$upstream"
  (cd "$monorepo" && splice pull -m e lib >/dev/null 2>&1)
}
