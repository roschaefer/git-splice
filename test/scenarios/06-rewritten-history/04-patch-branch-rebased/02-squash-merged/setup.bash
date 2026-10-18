# See README.md in this directory. The steps from there to the squash
# merge are in README.md itself, with a drawing after each.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_squash_merged() {
  scenario_patch_branch_rebased "$@"
}
