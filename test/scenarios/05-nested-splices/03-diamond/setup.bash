# See README.md in this directory. Each upstream is a bare repository next
# to <upstream>, reached by a URL that's the same on every run, so .splice
# and the commits that contain it are too.
scenario_diamond() {
  local monorepo="$1" upstream="$2" app
  # The shared library C.
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "c seed"
  # The apps A and B, each with C spliced in at c/.
  for app in a b; do
    make_bare_repo "$upstream-$app"
    seed_bare_repo "$upstream-$app" "$app seed"
    splice_into_upstream "$upstream-$app" https://git.example.com/c.git "$upstream" c
  done
  init_monorepo "$monorepo"
  git -C "$monorepo" config "url.$upstream.insteadOf" https://git.example.com/c.git
  git -C "$monorepo" config "url.$upstream-a.insteadOf" https://git.example.com/a.git
  git -C "$monorepo" config "url.$upstream-b.insteadOf" https://git.example.com/b.git
}
