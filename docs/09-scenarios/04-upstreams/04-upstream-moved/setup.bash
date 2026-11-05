# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../../01-everyday-sync/02-up-to-date/02-push-ahead/setup.bash"

scenario_upstream_moved() {
  local monorepo="$1" upstream="$2"
  scenario_push_ahead "$monorepo" "$upstream"
  # The upstream's new home, with the same commits.
  git clone -q --bare "$upstream" "$upstream-moved"
}
