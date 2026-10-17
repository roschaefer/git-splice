# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../../01-everyday-sync/02-up-to-date/setup.bash"

scenario_shared_remote_url() {
  local monorepo="$1" upstream="$2"
  scenario_up_to_date "$monorepo" "$upstream"
  add_splice "$monorepo" "$upstream" "vendor/b"
}
