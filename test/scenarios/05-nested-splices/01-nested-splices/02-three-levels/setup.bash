# See README.md in this directory. c's upstream is the bare repository
# <upstream>-c.git, spliced into b's at c/, which is spliced into a's at
# b/, as in the parent scenario. b's and c's are reached as $3 and $4 if
# given, e.g. URLs that url.<path>.insteadOf maps to them.
source "$(dirname "${BASH_SOURCE[0]}")/../setup.bash"

scenario_three_levels() {
  local monorepo="$1" upstream="$2" upstream_b="${2%.git}-b.git" upstream_c="${2%.git}-c.git" work
  local b_url="${3:-$upstream_b}" c_url="${4:-$upstream_c}"
  make_bare_repo "$upstream_c"
  seed_bare_repo "$upstream_c" "c seed"
  make_bare_repo "$upstream_b"
  seed_bare_repo "$upstream_b" "b seed"
  # b's upstream splices c in at c/.
  work="$(mktemp -d)"
  git clone -q "$upstream_b" "$work"
  git -C "$work" config user.name "Test"
  git -C "$work" config user.email "test@example.com"
  add_splice "$work" "$c_url" c
  git -C "$work" push -q origin HEAD:main
  rm -rf "$work"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "a seed"
  # a's upstream splices b in at b/, with c in it.
  work="$(mktemp -d)"
  git clone -q "$upstream" "$work"
  git -C "$work" config user.name "Test"
  git -C "$work" config user.email "test@example.com"
  add_splice "$work" "$b_url" b
  git -C "$work" push -q origin HEAD:main
  rm -rf "$work"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" vendor/a
  fetch_splice "$monorepo" "$b_url"
  fetch_splice "$monorepo" "$c_url"
}
