# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_uncommitted_changes() {
  local monorepo="$1" upstream="$2"
  scenario_push_ahead "$monorepo" "$upstream"
  echo "uncommitted change" >>"$monorepo/vendor/a/file.txt"
}
