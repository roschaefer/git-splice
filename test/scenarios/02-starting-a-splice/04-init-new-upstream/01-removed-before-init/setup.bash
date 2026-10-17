# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_removed_before_init() {
  local monorepo="$1" upstream="$2"
  scenario_init_new_upstream "$monorepo" "$upstream"
  commit_local "$monorepo" "lib/a" "password = hunter2" config.txt
  (
    cd "$monorepo"
    git rm -q lib/a/config.txt
    git commit -q -m "remove the password again"
  )
}
