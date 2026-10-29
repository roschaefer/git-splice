# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_unspliced_then_cloned_again() {
  local monorepo="$1" upstream="$2"
  scenario_init_new_upstream "$monorepo" "$upstream"
  (
    cd "$monorepo"
    splice init lib/a "$upstream"
    splice push lib/a
  )
}
