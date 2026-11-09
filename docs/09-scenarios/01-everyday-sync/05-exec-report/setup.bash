source "$(dirname "${BASH_SOURCE[0]}")/../../01-everyday-sync/02-up-to-date/01-pull-ahead/setup.bash"

scenario_exec_report() {
  scenario_pull_ahead "$@"
}
