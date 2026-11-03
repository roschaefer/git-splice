# See README.md in this directory. Each upstream is a bare repository next
# to <upstream>, reached by a URL that's the same on every run, so .splice
# and the commits that contain it are too.
scenario_cycle() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  git -C "$monorepo" config "url.$upstream.insteadOf" https://git.example.com/a.git
  add_splice "$monorepo" https://git.example.com/a.git vendor/a
  # The monorepo is published too, as m.
  make_bare_repo "$upstream-m"
  git -C "$monorepo" config "url.$upstream-m.insteadOf" https://git.example.com/m.git
  git -C "$monorepo" push -q https://git.example.com/m.git main
  # a's upstream splices the monorepo in at i/.
  splice_into_upstream "$upstream" https://git.example.com/m.git "$upstream-m" i
}
