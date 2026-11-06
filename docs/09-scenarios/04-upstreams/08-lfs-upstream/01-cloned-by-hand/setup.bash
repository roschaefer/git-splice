# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_cloned_by_hand() {
  local monorepo="$1" upstream="$2"
  scenario_lfs_upstream "$monorepo" "$upstream"
  (
    cd "$monorepo"
    GIT_LFS_SKIP_SMUDGE=1 splice clone "file://$upstream" vendor/a
    git lfs fetch "file://$upstream" "refs/splices/$(splice key vendor/a)/heads/main"
    git lfs checkout vendor/a
    git push -q origin main
  )
}
