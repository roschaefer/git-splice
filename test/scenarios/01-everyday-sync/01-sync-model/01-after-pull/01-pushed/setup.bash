# See README.md in this directory. Commits are named as in the drawings
# there, pushed.drawio.svg and pushed-and-bumped.drawio.svg.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_pushed() {
  local monorepo="$1" upstream="$2"
  scenario_after_pull "$monorepo" "$upstream"
  (
    cd "$monorepo"
    splice push lib >/dev/null 2>&1
  )
}
