# See README.md in this directory. The fork is the bare repository
# <upstream>-fork.git, a copy of <upstream> with a commit of its own. The
# original and the fork are reached as $3 and $4 if given, e.g. URLs that
# url.<path>.insteadOf maps to them.
scenario_several_upstreams() {
  local monorepo="$1" upstream="$2" fork="${2%.git}-fork.git"
  local origin_url="${3:-$upstream}"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  git clone -q --bare "$upstream" "$fork"
  seed_bare_repo "$fork" "fork patch"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$origin_url" vendor/a
}
