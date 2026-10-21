# See README.md in this directory.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

# The original and the fork are reached as $3 and $4 if given, as in the
# scenario above.
scenario_original_without_the_patch() {
  local monorepo="$1" upstream="$2" fork="${2%.git}-fork.git"
  scenario_several_upstreams "$@"
  (
    cd "$monorepo"
    git config --file vendor/a/.splice upstream.fork.url "${4:-$fork}"
    git config --file vendor/a/.splice splice.default-upstream fork
    git commit -q -m "vendor/a: work with the company fork" -- vendor/a/.splice
    splice pull vendor/a >/dev/null 2>&1
  )
  seed_bare_repo "$upstream" "original release" main release.txt
  (cd "$monorepo" && splice fetch --upstream origin vendor/a >/dev/null 2>&1)
}
