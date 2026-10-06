# See README.md in this directory. The inner upstream is the bare
# repository <upstream>-b.git (without .git), reached as $3 if given, e.g.
# a URL that url.<path>.insteadOf maps to it.
scenario_nested_splices() {
  local monorepo="$1" upstream="$2" inner="${2%.git}-b.git" work
  local inner_url="${3:-$inner}"
  make_bare_repo "$inner"
  seed_bare_repo "$inner" "b seed"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "a seed"
  # a's upstream uses git splice itself: b is spliced in at b/.
  work="$(mktemp -d)"
  git clone -q "$upstream" "$work"
  git -C "$work" config user.name "Test"
  git -C "$work" config user.email "test@example.com"
  add_splice "$work" "$inner_url" b
  git -C "$work" push -q origin HEAD:main
  rm -rf "$work"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" vendor/a
  fetch_splice "$monorepo" "$inner_url" vendor/a/b
}
