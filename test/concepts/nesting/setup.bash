# See diamond.md and cycle.md in this directory. Each upstream is a bare
# repository next to <upstream>, reached by a URL that's the same on every
# run, so .splice and the commits that contain it are too.

# Clones bare repository <upstream>, splices <url> in at <path> there, and
# pushes. <upstream>'s users reach <url> through url.<url_base>.insteadOf.
splice_into_upstream() {
  local upstream="$1" url="$2" url_base="$3" path="$4" work
  work="$(mktemp -d)"
  git clone -q "$upstream" "$work"
  git -C "$work" config user.name "Test"
  git -C "$work" config user.email "test@example.com"
  git -C "$work" config "url.$url_base.insteadOf" "$url"
  add_splice "$work" "$url" "$path"
  git -C "$work" push -q origin HEAD:main
  rm -rf "$work"
}

scenario_diamond() {
  local monorepo="$1" upstream="$2" app
  # The shared library S.
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "s seed"
  # The apps A and B, each with S spliced in at s/.
  for app in a b; do
    make_bare_repo "$upstream-$app"
    seed_bare_repo "$upstream-$app" "$app seed"
    splice_into_upstream "$upstream-$app" https://git.example.com/s.git "$upstream" s
  done
  init_monorepo "$monorepo"
  git -C "$monorepo" config "url.$upstream.insteadOf" https://git.example.com/s.git
  git -C "$monorepo" config "url.$upstream-a.insteadOf" https://git.example.com/a.git
  git -C "$monorepo" config "url.$upstream-b.insteadOf" https://git.example.com/b.git
}

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
