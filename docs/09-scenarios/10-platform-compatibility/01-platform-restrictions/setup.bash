source "$(dirname "${BASH_SOURCE[0]}")/../../01-everyday-sync/02-up-to-date/02-push-ahead/setup.bash"

scenario_platform_restrictions() {
  scenario_push_ahead "$1" "$2"
}
