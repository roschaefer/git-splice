# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../../01-everyday-sync/02-up-to-date/02-push-ahead/setup.bash"

# Like push-ahead, with the local commit pushed.
scenario_pushed_then_rebased() {
  local monorepo="$1" upstream="$2"
  scenario_push_ahead "$monorepo" "$upstream" "b: a local change"
  (cd "$monorepo" && splice push vendor/a >/dev/null 2>&1)
}
