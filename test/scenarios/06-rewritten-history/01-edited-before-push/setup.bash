# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../../01-everyday-sync/02-up-to-date/02-push-ahead/setup.bash"

# Like push-ahead, with the unpushed commit's message meant for the
# monorepo only.
scenario_edited_before_push() {
  local monorepo="$1" upstream="$2"
  scenario_push_ahead "$monorepo" "$upstream" "fix, see INTERNAL-123"
}
