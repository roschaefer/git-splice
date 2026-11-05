# See README.md in this directory.
scenario_upstreams() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  git -C "$monorepo" config "url.$upstream.insteadOf" https://git.example.com/s.git
  (
    cd "$monorepo" || return
    splice clone https://git.example.com/s.git app-a/s >/dev/null 2>&1 &&
      splice clone https://git.example.com/s.git app-b/s >/dev/null 2>&1
  )
}
