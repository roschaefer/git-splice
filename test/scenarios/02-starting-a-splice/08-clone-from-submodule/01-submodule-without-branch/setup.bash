# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_submodule_without_branch() {
  scenario_clone_from_submodule "$@"
}
