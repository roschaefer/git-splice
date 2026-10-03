# See README.md in this directory.
scenario_never_fetched() {
  local monorepo="$1" upstream="$2" original
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  original="$(mktemp -d)/monorepo"
  init_monorepo "$original"
  add_splice "$original" "$upstream" "vendor/a"
  # A fresh clone of the monorepo: the commits are there, but neither the
  # refs with upstream's branches nor upstream's own commits are.
  # --no-local: a local clone would hard-link every object, upstream's too.
  git clone -q --no-local "$original" "$monorepo"
  rm -rf "$(dirname "$original")"
  git -C "$monorepo" remote remove origin
  git -C "$monorepo" config user.name "Test"
  git -C "$monorepo" config user.email "test@example.com"
  git -C "$monorepo" config init.defaultBranch main
}
