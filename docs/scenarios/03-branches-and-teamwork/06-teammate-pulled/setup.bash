# See README.md in this directory.
scenario_teammate_pulled() {
  local monorepo="$1" upstream="$2" origin="$1-origin.git" alice="$1-alice"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "k: seed"

  # Alice's monorepo, shared through $origin. A URL that's the same on
  # every run keeps .splice, and the commits that contain it, the same.
  init_monorepo "$alice"
  git -C "$alice" config "url.$upstream.insteadOf" https://git.example.com/a.git
  (cd "$alice" && splice clone -m "a: clone vendor/a" https://git.example.com/a.git vendor/a >/dev/null 2>&1)
  git clone -q --bare "$alice" "$origin"
  git -C "$alice" remote add origin "$origin"

  # Bob clones the monorepo and fetches the splice: this is $monorepo.
  git clone -q "$origin" "$monorepo"
  git -C "$monorepo" config user.name "Test"
  git -C "$monorepo" config user.email "test@example.com"
  git -C "$monorepo" config "url.$upstream.insteadOf" https://git.example.com/a.git
  (cd "$monorepo" && splice fetch vendor/a >/dev/null 2>&1)

  # Alice pulls the upstream's change and pushes the monorepo. Bob pulls
  # the monorepo, but doesn't fetch the splice.
  seed_bare_repo "$upstream" "l: upstream change"
  (cd "$alice" && splice pull -m "p: pull vendor/a" vendor/a >/dev/null 2>&1 && git push -q origin main)
  git -C "$monorepo" pull -q
}
