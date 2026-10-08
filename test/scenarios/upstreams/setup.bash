# See README.md in this directory.
scenario_upstreams() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  # Two URLs for the same repository, both the same on every run, so
  # .splice and the commits that contain it are too.
  git -C "$monorepo" config "url.$upstream.insteadOf" https://git.example.com/s.git
  git -C "$monorepo" config --add "url.$upstream.insteadOf" https://mirror.example.com/s.git
}
