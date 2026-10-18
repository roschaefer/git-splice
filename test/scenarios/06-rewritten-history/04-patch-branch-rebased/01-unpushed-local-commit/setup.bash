# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_unpushed_local_commit() {
  scenario_patch_branch_rebased "$1" "$2"
  commit_local "$1" vendor/a "local change" local.txt
}
