# See README.md in this directory. The splice reaches the upstream as $3
# if given, e.g. a URL that url.<path>.insteadOf maps to it.
scenario_up_to_date() {
  local monorepo="$1" upstream="$2" url="${3:-$2}"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$url" "vendor/a"
}
