# See README.md in this directory.
scenario_splice_refs() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  seed_bare_repo "$upstream" "parser fix" fix-parser
  init_monorepo "$monorepo"
  # A URL that's the same on every run, so .splice and the commits that
  # contain it are too.
  git -C "$monorepo" config "url.$upstream.insteadOf" https://git.example.com/a.git
}
