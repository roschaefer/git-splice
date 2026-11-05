# See README.md in this directory.
scenario_git_trace() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  git -C "$monorepo" config "url.$upstream.insteadOf" https://git.example.com/lib.git
  (
    cd "$monorepo" || return
    splice clone https://git.example.com/lib.git lib >/dev/null 2>&1
  )
  commit_local "$monorepo" lib "fix parse()"
}
