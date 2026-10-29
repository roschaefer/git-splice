# See README.md in this directory. b's upstream is the bare
# repository <upstream>-b.git (without .git), reached as $3 if given, e.g.
# a URL that url.<path>.insteadOf maps to it.
scenario_nested_splices() {
  local monorepo="$1" upstream="$2" upstream_b="${2%.git}-b.git" work
  local b_url="${3:-$upstream_b}"
  make_bare_repo "$upstream_b"
  seed_bare_repo "$upstream_b" "b seed"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "a seed"
  # a's upstream uses git splice itself: b is spliced in at b/.
  work="$(mktemp -d)"
  git clone -q "$upstream" "$work"
  git -C "$work" config user.name "Test"
  git -C "$work" config user.email "test@example.com"
  add_splice "$work" "$b_url" b
  git -C "$work" push -q origin HEAD:main
  rm -rf "$work"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" vendor/a
  fetch_splice "$monorepo" "$b_url" vendor/a/b
}
