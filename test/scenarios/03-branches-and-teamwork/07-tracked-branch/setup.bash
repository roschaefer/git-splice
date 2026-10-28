# See README.md in this directory. Each splice has its own upstream, next
# to $2: $2 without .git, then -<name>.git, e.g. upstream-a.git.
scenario_tracked_branch() {
  local monorepo="$1" upstream="${2%.git}"
  init_monorepo "$monorepo"
  add_tracked_branch_splice "$monorepo" "$upstream" a k
  add_tracked_branch_splice "$monorepo" "$upstream" b m
  # a's team works on development, b's reviews on review.
  seed_bare_repo "$upstream-a.git" "l: development change" development
  seed_bare_repo "$upstream-b.git" "n: review change" review
  git -C "$monorepo" checkout -q -b feature
}

# Clones splice vendor/<name> from a new upstream, $2-<name>.git, seeded
# with commit <label>.
add_tracked_branch_splice() {
  local monorepo="$1" upstream="$2-$3.git" name="$3" label="$4"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "$label: seed"
  # A URL that's the same on every run keeps the upstream's key, a or b.
  git -C "$monorepo" config "url.$upstream.insteadOf" "https://git.example.com/$name.git"
  (cd "$monorepo" && splice clone -m "$name: clone vendor/$name" "https://git.example.com/$name.git" "vendor/$name" >/dev/null 2>&1)
}
