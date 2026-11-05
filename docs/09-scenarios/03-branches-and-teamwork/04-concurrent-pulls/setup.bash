# See README.md in this directory.
scenario_concurrent_pulls() {
  local monorepo="$1" upstream="$2" origin="$1-origin.git" alice="$1-alice"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"

  # Alice's monorepo, shared through $origin. A URL that's the same on
  # every run keeps .splice, and the commits that contain it, the same.
  init_monorepo "$alice"
  git -C "$alice" config "url.$upstream.insteadOf" https://git.example.com/a.git
  (cd "$alice" && splice clone https://git.example.com/a.git vendor/a >/dev/null 2>&1)
  git clone -q --bare "$alice" "$origin"
  git -C "$alice" remote add origin "$origin"

  # Bob clones the monorepo: this is $monorepo.
  git clone -q "$origin" "$monorepo"
  git -C "$monorepo" config user.name "Test"
  git -C "$monorepo" config user.email "test@example.com"
  git -C "$monorepo" config "url.$upstream.insteadOf" https://git.example.com/a.git

  # Alice pulls the upstream's first change and pushes the monorepo.
  seed_bare_repo "$upstream" "upstream 1"
  (cd "$alice" && splice pull vendor/a >/dev/null 2>&1 && git push -q origin main)

  # Later, Bob pulls the upstream's second change, without pulling the
  # monorepo first, then fetches the monorepo.
  seed_bare_repo "$upstream" "upstream 2"
  (cd "$monorepo" && splice pull vendor/a >/dev/null 2>&1 && git fetch -q)
}
