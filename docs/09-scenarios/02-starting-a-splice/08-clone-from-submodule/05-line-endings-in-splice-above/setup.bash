# See README.md in this directory. The submodules reach their upstreams,
# $UPSTREAM and $UPSTREAM-inner, as $3 and $4 if given.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_line_endings_in_splice_above() {
  local monorepo="$1" upstream="$2" inner="$2-inner"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "inner"
  commit_raw_file "$inner" settings.h '#define X 1\r\n'
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  commit_raw_file "$upstream" .gitattributes '*.h text eol=lf\n'
  add_upstream_submodule "$upstream" "${4:-$inner}" libs/inner
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    git -c protocol.file.allow=always submodule add -q "${3:-$upstream}" vendor/a
    git -c protocol.file.allow=always submodule update -q --init --recursive
    git commit -q -m "add vendor/a as a submodule"
  )
}
