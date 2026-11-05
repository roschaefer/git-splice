# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_submodule_with_branch() {
  local monorepo="$1" upstream="$2"
  scenario_clone_from_submodule "$@"
  git -C "$upstream" branch stable main~1
  seed_bare_repo "$upstream" "stable fix" stable
  (
    cd "$monorepo"
    git config --file .gitmodules submodule.vendor/a.branch stable
    git commit -q -m "vendor/a follows stable" .gitmodules
  )
}
