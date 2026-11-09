source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_push_to_upstreams() {
  local monorepo="$1" upstream="$2" upstream_b="$2-b.git"
  scenario_lfs_upstream "$monorepo" "$upstream"
  make_bare_repo "$upstream_b"
  commit_lfs_file "$upstream_b" model.bin "b weights, version 1" "add b's model"
  (
    cd "$monorepo" || return
    GIT_LFS_SKIP_SMUDGE=1 splice clone "file://$upstream" vendor/a
    GIT_LFS_SKIP_SMUDGE=1 splice clone "file://$upstream_b" vendor/b
  )
  commit_lfs_file "$upstream" model.bin "weights, version 2" "train a's model again"
  commit_lfs_file "$upstream_b" model.bin "b weights, version 2" "train b's model again"
}
