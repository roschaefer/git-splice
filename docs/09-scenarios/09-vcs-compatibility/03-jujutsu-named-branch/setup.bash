source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_jujutsu_named_branch() {
  scenario_vcs_compatibility "$1" "$2"
}
