# See README.md in this directory. b's upstream is the bare repository
# <upstream>-b.git (without .git), reached as $3 if given, e.g. a URL that
# url.<path>.insteadOf maps to it. The monorepo is empty.
scenario_nested_default_branch() {
  local monorepo="$1" upstream="$2" upstream_b="${2%.git}-b.git" work
  local b_url="${3:-$upstream_b}"
  make_bare_repo "$upstream_b" master
  seed_bare_repo "$upstream_b" "b seed" master
  make_bare_repo "$upstream" master
  seed_bare_repo "$upstream" "a seed" master
  # a's upstream uses git splice itself: b is spliced in at b/. Both
  # default to master, so b's .splice doesn't name a default branch.
  work="$(mktemp -d)"
  git clone -q "$upstream" "$work"
  git -C "$work" config user.name "Test"
  git -C "$work" config user.email "test@example.com"
  add_splice "$work" "$b_url" b master
  git -C "$work" push -q origin HEAD:master
  rm -rf "$work"
  init_monorepo "$monorepo"
}
