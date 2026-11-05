# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../../01-everyday-sync/02-up-to-date/02-push-ahead/01-pushed-then-pulled/setup.bash"

scenario_bumped_on_a_feature_branch() {
  local monorepo="$1" upstream="$2"
  scenario_pushed_then_pulled "$monorepo" "$upstream"
  (cd "$monorepo" && splice pull --bump -m "a: bump vendor/a" vendor/a >/dev/null 2>&1)
}
