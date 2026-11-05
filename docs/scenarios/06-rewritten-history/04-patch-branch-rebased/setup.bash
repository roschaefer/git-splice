# See README.md in this directory. The splice reaches the upstream as $3
# if given, e.g. a URL that url.<path>.insteadOf maps to it.
scenario_patch_branch_rebased() {
  local monorepo="$1" upstream="$2" url="${3:-$2}"
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "k: seed"
  # A fork's patch branch: the upstream's main plus two patches of its own.
  seed_bare_repo "$upstream" "p: patch" patches
  seed_bare_repo "$upstream" "other patch" patches other.txt
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$url" "vendor/a" patches "a: add vendor/a"
  (
    cd "$monorepo"
    git config --file vendor/a/.splice upstream.origin.default-branch patches
    git commit -q -a --amend --no-edit
  )

  # The upstream's main takes the first patch, reworded, and the patch
  # branch is rebased onto it: that patch drops out, the other one gets a
  # new commit on top of main.
  seed_bare_repo "$upstream" "m: patch, reworded upstream"
  git -C "$upstream" update-ref refs/heads/patches refs/heads/main
  seed_bare_repo "$upstream" "other patch" patches other.txt
  fetch_splice "$monorepo" "$url" "vendor/a"
}
