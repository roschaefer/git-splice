# See README.md in this directory.
scenario_feature_branch_behind_default_branch() {
  local monorepo="$1" upstream="$2"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "k: seed"

  # A URL that's the same on every run keeps .splice, and the commits
  # that contain it, the same.
  init_monorepo "$monorepo"
  git -C "$monorepo" config "url.$upstream.insteadOf" https://git.example.com/a.git
  (cd "$monorepo" && splice clone -m "a: clone vendor/a" https://git.example.com/a.git vendor/a)

  # The feature branch's change is pushed: upstream's 'feature', the PR.
  git -C "$monorepo" checkout -q -b feature
  commit_local "$monorepo" vendor/a "b: feature change" feature.txt
  (cd "$monorepo" && splice push vendor/a)

  # Upstream's main moves on, and the monorepo's main pulls it in. The
  # feature branch isn't rebased onto it yet, on either side.
  seed_bare_repo "$upstream" "m: bump dep" main lock.txt
  git -C "$monorepo" checkout -q main
  (cd "$monorepo" && splice pull -m "p: pull the dependency update" vendor/a)
  git -C "$monorepo" checkout -q feature
}
