# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_submodule_with_branch_dot() {
  local monorepo="$1" upstream="$2"
  scenario_clone_from_submodule "$@"
  (
    cd "$monorepo"
    git config --file .gitmodules submodule.vendor/a.branch .
    git commit -q -m "vendor/a follows the branch named like the monorepo's" .gitmodules
  )
}
