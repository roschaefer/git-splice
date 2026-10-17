# See README.md in this directory.
scenario_upstream_rewritten_equal_tree() {
  local monorepo="$1" upstream="$2" tree rewritten
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  seed_bare_repo "$upstream" "release"
  init_monorepo "$monorepo"
  add_splice "$monorepo" "$upstream" "vendor/a"

  # Upstream rewrites its history, e.g. to remove a secret from an old
  # commit, and force-pushes: one new root commit with the same files.
  tree="$(git -C "$upstream" rev-parse 'main^{tree}')"
  rewritten="$(git -C "$upstream" -c user.name=Test -c user.email=test@example.com \
    commit-tree "$tree" -m "release, history rewritten")"
  git -C "$upstream" update-ref refs/heads/main "$rewritten"
  fetch_splice "$monorepo" "$upstream" "vendor/a"
}
