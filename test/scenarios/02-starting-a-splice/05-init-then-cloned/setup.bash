# See README.md in this directory.
scenario_init_then_cloned() {
  local monorepo="$1" upstream="$2" original="$1-original"
  make_bare_repo "$upstream"
  # Someone else's monorepo, where lib/a was made a splice and published.
  init_monorepo "$original"
  commit_local "$original" "lib/a" "first version"
  (
    cd "$original"
    splice init lib/a "$upstream" >/dev/null 2>&1
    splice push lib/a >/dev/null 2>&1
  )
  commit_local "$original" "lib/a" "second version"
  (cd "$original" && splice push lib/a >/dev/null 2>&1)
  # A fresh clone of that monorepo, as a colleague would make it.
  git clone -q --no-local "$original" "$monorepo"
  git -C "$monorepo" config user.name "Test"
  git -C "$monorepo" config user.email "test@example.com"
}
