source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_sapling_git_index() {
  scenario_vcs_compatibility "$1" "$2"
  add_splice "$1" https://git.example.com/lib.git vendor/lib
}
