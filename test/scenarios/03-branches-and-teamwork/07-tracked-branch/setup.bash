# See README.md in this directory. Each splice has its own upstream, next
# to $2: $2 without .git, then -<name>.git, e.g. upstream-a.git.
scenario_tracked_branch() {
  local monorepo="$1" upstream="${2%.git}" name
  init_monorepo "$monorepo"
  for name in a b; do
    make_bare_repo "$upstream-$name.git"
    seed_bare_repo "$upstream-$name.git" "seed"
    # A URL that's the same on every run keeps the upstream's key, a or b.
    git -C "$monorepo" config "url.$upstream-$name.git.insteadOf" "https://git.example.com/$name.git"
    (cd "$monorepo" && splice clone -m "clone vendor/$name" "https://git.example.com/$name.git" "vendor/$name" >/dev/null 2>&1)
  done
  # a's team works on development, b's reviews on review.
  seed_bare_repo "$upstream-a.git" "a: development change" development
  seed_bare_repo "$upstream-b.git" "b: review change" review
  git -C "$monorepo" checkout -q -b feature
}
