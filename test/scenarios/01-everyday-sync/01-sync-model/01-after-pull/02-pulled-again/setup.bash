# See README.md in this directory. Commits are named as in the drawing.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_pulled_again() {
  local monorepo="$1" upstream="$2"
  scenario_after_pull "$monorepo" "$upstream"
  commit_local "$monorepo" "lib" "f" f.txt
  seed_bare_repo "$upstream" "o" main o.txt
  (cd "$monorepo" && splice pull -m g lib >/dev/null 2>&1)
}
