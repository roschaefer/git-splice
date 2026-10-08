# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

# Like push-ahead, with the unpushed commit's message meant for the
# monorepo only.
scenario_edited_before_push() {
  local monorepo="$1" upstream="$2"
  scenario_up_to_date "$monorepo" "$upstream"
  commit_local "$monorepo" "vendor/a" "fix, see INTERNAL-123"
}
