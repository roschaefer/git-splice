# See README.md in this directory. Commits are named as in the drawings
# there, fork.drawio.svg and fork-merged.drawio.svg.

scenario_contributing_through_a_fork() {
  local monorepo="$1" upstream="$2" fork="${2%.git}-fork.git"
  local origin_url="${3:-$upstream}" fork_url="${4:-$fork}"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "k: seed"
  seed_bare_repo "$upstream" "m: a second commit"
  git clone -q --bare "$upstream" "$fork"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$origin_url" vendor/a
  (
    cd "$monorepo"
    git config --file vendor/a/.splice upstream.fork.url "$fork_url"
    git config --file vendor/a/.splice upstream.fork.default-branch patches
    git config --file vendor/a/.splice splice.default-upstream fork
    git commit -q -m "follow the fork's patches" -- vendor/a/.splice
  )
}
