# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../../01-everyday-sync/02-up-to-date/02-push-ahead/setup.bash"

scenario_feature_branch_from_main() {
  local monorepo="$1" upstream="$2"
  scenario_push_ahead "$monorepo" "$upstream"
  git -C "$monorepo" checkout -q -b feature
  git -C "$monorepo" branch -f main HEAD~1
}
