# See README.md in this directory. Commits are named as in the drawing
# there, pushed-and-bumped.drawio.svg.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_pushed_and_bumped() {
  local monorepo="$1" upstream="$2"
  scenario_after_pull "$monorepo" "$upstream"
  (
    cd "$monorepo"
    splice push vendor/a >/dev/null 2>&1
    splice pull --bump vendor/a >/dev/null 2>&1
  )
}
