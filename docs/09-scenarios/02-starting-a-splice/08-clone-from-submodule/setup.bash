# See README.md in this directory. The submodule reaches the upstream as
# $3 if given, e.g. a URL that url.<path>.insteadOf maps to it.
scenario_clone_from_submodule() {
  local monorepo="$1" upstream="$2" url="${3:-$2}"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  (
    cd "$monorepo"
    git -c protocol.file.allow=always submodule add -q "$url" vendor/a
    git commit -q -m "add vendor/a as a submodule"
  )
  seed_bare_repo "$upstream" "newer"
}
