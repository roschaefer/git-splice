# See README.md in this directory.
scenario_splice_identity() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  # A URL that is the same on every run, so .splice and the commits that
  # contain it are too.
  git -C "$monorepo" config "url.$upstream.insteadOf" https://git.example.com/a.git
}
