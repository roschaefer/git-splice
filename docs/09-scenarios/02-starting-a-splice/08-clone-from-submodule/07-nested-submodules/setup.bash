# See README.md in this directory. The submodules reach their upstreams,
# $UPSTREAM and $UPSTREAM-inner, as $3 and $4 if given.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_nested_submodules() {
  local monorepo="$1" upstream="$2" inner="$2-inner"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "inner"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  add_upstream_submodule "$upstream" "${4:-$inner}" libs/inner
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    git -c protocol.file.allow=always submodule add -q "${3:-$upstream}" vendor/a
    git -c protocol.file.allow=always submodule update -q --init --recursive
    git config --file .gitmodules submodule.vendor/a.branch main
    git add .gitmodules
    git commit -q -m "add vendor/a as a submodule"
  )
}
