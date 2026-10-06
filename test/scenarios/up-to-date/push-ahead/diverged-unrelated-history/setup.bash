# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_diverged_unrelated_history() {
  local monorepo="$1" upstream="$2"
  scenario_push_ahead "$monorepo" "$upstream"

  # Blow away upstream and replace it with a completely unrelated history.
  rm -rf "$upstream"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "brand new unrelated history"
  fetch_splice "$monorepo" "$upstream" "vendor/a"
}
