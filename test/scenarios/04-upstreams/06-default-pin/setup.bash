# See README.md in this directory.
scenario_default_pin() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream" main
  seed_bare_repo "$upstream" "v1"
  git -C "$upstream" tag v1 main
  init_monorepo "$monorepo"
  (
    cd "$monorepo" &&
      splice clone "$upstream" vendor/a >/dev/null 2>&1 &&
      git config --file vendor/a/.splice upstream.origin.default-pin v1 &&
      git commit -q -m "vendor/a: pin v1" -- vendor/a/.splice
  )
  seed_bare_repo "$upstream" "v2"
  git -C "$upstream" tag v2 main
}
