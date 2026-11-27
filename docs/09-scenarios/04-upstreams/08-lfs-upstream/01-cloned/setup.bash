# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_cloned() {
  local monorepo="$1" upstream="$2"
  scenario_lfs_upstream "$monorepo" "$upstream"
  (
    cd "$monorepo"
    splice clone "file://$upstream" vendor/a
    git push -q origin main
  )
}
