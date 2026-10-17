# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_local_edit_in_the_squash() {
  local monorepo="$1" upstream="$2"
  scenario_up_to_date "$monorepo" "$upstream"
  # As in the parent scenario, a pull on a feature branch, squash-merged
  # into main; but the feature branch also edited the folder, so the
  # squash merge holds the pull and the local edit in one commit.
  seed_bare_repo "$upstream" "upstream feature work" feature
  (
    cd "$monorepo"
    git checkout -q -b feature
    splice pull vendor/a >/dev/null 2>&1
    echo "local edit" >vendor/a/local.txt
    git add vendor/a
    git commit -q -m "local edit"
    git checkout -q main
    git merge -q --squash feature >/dev/null
    git commit -q -m "feature (squash-merged)"
    git branch -q -D feature
  )
}
