source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_sapling_metadata() {
  local monorepo="$1" upstream_repo="$2" release
  scenario_vcs_compatibility "$monorepo" "$upstream_repo" || return
  [[ "$(uname -s)" == Linux ]] || return 0
  (
    cd "$monorepo" || exit
    sl subtree import --url https://git.example.com/lib.git --rev main \
      --to-path vendor/lib -m "import lib"
  ) || return
  seed_bare_repo "$upstream_repo" "release adds compat" main src/compat.txt
  release="$(git --git-dir="$upstream_repo" rev-parse main)"
  (
    cd "$monorepo" || exit
    git switch -q -c release
    sl subtree merge --url https://git.example.com/lib.git -r "$release" --to-path vendor/lib
    sl commit -q -m "import release"
  ) || return
  (
    cd "$VCS_ROOT/splice-monorepo" || exit
    git switch -q -c release
    git splice pull --branch main vendor/lib
  )
}
