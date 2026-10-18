# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_squash_merged() {
  local monorepo="$1" upstream="$2"
  scenario_patch_branch_rebased "$monorepo" "$upstream"
  (
    cd "$monorepo"
    # main is protected: the pull happens on a local main, and its commit
    # moves to a pull request's branch, with a local change on top.
    splice pull vendor/a
    git switch -q -c take-the-release
    git switch -q main
    git reset -q --hard HEAD~1
    git switch -q take-the-release
  )
  commit_local "$monorepo" vendor/a "local change" local.txt
  (
    cd "$monorepo"
    # The pull request is squash-merged.
    git switch -q main
    git merge -q --squash take-the-release
    git commit -q -m "vendor/a: take the release, and a local change (#1)"
  )
}
