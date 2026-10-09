# See README.md in this directory.
scenario_splice_identity() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  # A fork of the upstream, with a commit the original doesn't have.
  git clone -q --bare "$upstream" "$upstream-fork"
  seed_bare_repo "$upstream-fork" "fork fix"
  init_monorepo "$monorepo"
  # URLs that are the same on every run, so .splice and the commits that
  # contain it are too.
  git -C "$monorepo" config "url.$upstream.insteadOf" https://git.example.com/a.git
  git -C "$monorepo" config "url.$upstream-fork.insteadOf" https://git.example.com/a-fork.git
}
