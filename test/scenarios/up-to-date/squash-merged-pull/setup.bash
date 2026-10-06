# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_squash_merged_pull() {
  local monorepo="$1" upstream="$2"
  scenario_up_to_date "$monorepo" "$upstream"
  # Someone else's work on a feature branch upstream, pulled into the
  # monorepo's feature branch, which is then squash-merged into main.
  seed_bare_repo "$upstream" "upstream feature work" feature
  (
    cd "$monorepo"
    git checkout -q -b feature
    splice pull vendor/a >/dev/null 2>&1
    git checkout -q main
    git merge -q --squash feature >/dev/null
    git commit -q -m "feature (squash-merged)"
    git branch -q -D feature
  )
  commit_local "$monorepo" "vendor/a" "local change"
}
