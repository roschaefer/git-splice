# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_retrained_upstream() {
  local monorepo="$1" upstream="$2"
  scenario_cloned_by_hand "$monorepo" "$upstream"
  commit_lfs_file "$upstream" model.bin "weights, version 2" "train the model again"
}
